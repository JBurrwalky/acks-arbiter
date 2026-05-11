# Phase 10 — Class-Specific Sub-Tab — Granular Build Plan

> **Authority:** Implements `docs/domain-roadmap-corrected.md` Phase 10 (line 411+) and `generation/gdd-domain-tab.md` §12.
>
> **Status (2026-05-10):** Plan agreed with Jedidiah; Phase 10A.1 about to start. This document is the canonical Phase 10 build sequence and survives session compaction. Update the "Status" line and the per-sub-phase Status fields as work lands.

## Wave split (granular, per Jedidiah Q4)

| Sub-phase | Scope | Coverage | Status |
|---|---|---|---|
| **10A.1** | Sub-tab shell + `ClassBucketResolver` + visibility wiring + GDD updates per Q1-Q3 | 0 classes functional yet (shell only) | Pending |
| **10A.2** | Faith block (full) | Cleric / Bladedancer / Priestess / Shaman / Anti-Paladin / Dwarven Craftpriest / Darkblood Ruinguard / Lightblessed Wonderworker (secondary stack) | Pending |
| **10A.3** | Bardic Patronage block (Bard only — Chronicles of Battle aura + Solicit Followers) **PLUS** Garrison sub-tab proficiency-gated training launchers (train_troops / oversee_troop_training / inspect_troops) per Q14 | Bard (class-bucket); ANY class with Manual of Arms or equivalent (Garrison sub-tab) | Pending |
| **10B.1** | Magical Research block (research projects + libraries + workshops + magic-item creation + Lightblessed dual-list + sanctum apprentices/aspirants + Wonderworker-aspirant attrition) | Mage / Warlock / Witch / Elven Courtier / Elven Enchanter / Elven Spellsword / Elven Nightblade (secondary stack) / Lightblessed Wonderworker (primary stack) | Pending |
| **10B.2** | Trade block (monopoly + apprentices + Settlement-Panel cross-activations) | Venturer | Pending — depends on Phase 10B-prerequisite session (see §Q5 deliverable) |
| **10B.3** | Syndicate block (hijinks + crime & punishment + simplified-table NPC fast path) | Thief / Assassin / Elven Nightblade (primary stack) | Pending — depends on Phase 10B-prerequisite session |

After 10A.3 ships we have a playable end-to-end loop for the majority of classes. 10B.1-10B.3 backfill the remaining four classes that lean on Mercantile/Magical/Syndicate mechanics.

---

## Q&A resolutions (locked decisions)

These are folded into the per-sub-phase specs below. Any future deviation from these answers requires a fresh check-in with Jedidiah.

- **Q1.** All in-code, in-data, in-doc references to the class are **"Lightblessed Wonderworker"** for legal reasons. No "Nobiran" anywhere.
- **Q2.** Lightblessed apprentices/aspirants split **50/50** mage/cleric (no INT-vs-WIS dynamic assignment). Aspirants are 0-level Normal Men at creation; mage aspirants get INT boosted to 9 if rolled lower, cleric aspirants get WIS boosted to 9 if rolled lower. Promotion mechanic per Q20 [RESOLVED 2026-05-11] — see updated Q20 below. The prior "1d6/month-per-aspirant-for-6-months attrition" model is **scrapped** and is no longer the project-canonical resolution.
- **Q3.** Bard's surface is **"Bardic Patronage"** (per Q14 [RESOLVED 2026-05-11], it is now its own class bucket — not a variant of Garrison Training, since Garrison Training is no longer a class bucket). Content: RAW `hireling_inspiration` (Chronicles of Battle, +1 morale aura) + RAW `hall` (Solicit Followers, recruits 1d4+1×10 0-level mercenaries + 1d6 1st-3rd-level bards). Bards are NOT eligible for hijinks (RAW class-id allowlist) but CAN train troops if they take Manual of Arms proficiency — that surfaces in the Garrison sub-tab per Q14.
- **Q4.** Wave split per the table above. Plan documented here for compaction survival.
- **Q5.** Hijink/Mercantile get **full implementation** (not v1 stubs), but the **prerequisite subsystems** are built in a parallel session. Dependency summary lives in `docs/phase-10b-subsystem-dependencies.md`.
- **Q6.** Crime & Punishment full resolver: 2d6 + Cha + proficiency mods + attorney + bribery + evidence + interpleader + prior crimes + severity. Fines + prison time mechanically applied. Permanent-wound / amputation / execution outcomes logged but do NOT mutate combat-affecting character state in v1. Re-wire later.
- **Q7.** Single venturer claims monopoly atomically per settlement. NPC venturer rivals deferred to v1.1+.
- **Q8.** Per-hijink resolution per the roadmap, BUT for purely-NPC syndicates running off-camera in the world simulation, use the simplified `monthly_hijink_income_table` ([rules/acore-campaign-hijinks.xml:501-518](rules/acore-campaign-hijinks.xml:501)) as a perf shortcut. PC-involved syndicates always roll per-hijink.
- **Q9.** Mage's dungeon-under-tower hook: Magical Research block displays existing dungeon status (read-side); the dungeon-causes-encounters integration is a hook into the existing Phase 9A `domain_encounter_resolver`. The full dungeon-stocking-with-monsters system (room-by-room lair seeding per [rules/acore-campaign-hijinks.xml:545-611](rules/acore-campaign-hijinks.xml:545)) is **shortcut** in v1: dungeon presence simply increases encounter frequency for the domain. **MUST be documented in the build log entry** for the session that lands this hook so the future dungeon-system phase can rebuild the full mechanic.
- **Q10.** Settled-lair work + monster catalog work is done in the parallel monster-data session; Phase 10A.3 / 10B.1 may freely touch `domain_encounter_resolver.gd` and `monster_catalog.json` if needed.

- **Q11.** Divine casters with full `spell_research` ALSO get the Magical Research bucket alongside Faith. Affects: Cleric, Priestess, Shaman, Dwarven Craftpriest, Witch (all stack `[magical_research, faith]`). Bladedancer's `spell_research_and_minor_item_creation` is restricted and does NOT trigger MR. Per [docs/domain-roadmap-corrected.md] interpretation by Jedidiah 2026-05-10.

- **Q12.** Darkblood Ruinguard (renamed from Zaharan Ruinguard) is an **arcane caster** (`arcane_casting_in_armor` power), NOT a divine caster. The GDD §12.1 row had it wrong; corrected to `[magical_research]` (plus its previous garrison_training is removed per Q14).

- **Q13.** [SUPERSEDED by Q20 [RESOLVED 2026-05-11].] The earlier reading retained the standard sanctum's 1d6-month variability; Q20 collapses that to a fixed **4 months** universally (the expected value of 1d6 ≈ 3.5, rounded to 4). See Q20 below for the canonical mechanic.

- **Q20.** Sanctum aspirant promotion mechanic (universal, applies to Mage / Witch / Warlock / Elven Enchanter / Lightblessed Wonderworker sanctums). Every aspirant is created as a 0-level Normal Man with `intended_class` set at sanctum founding. For Lightblessed, the 50/50 mage/cleric split (per Q2) determines intent; for single-class casters, all aspirants share the caster's intent. Mage-intent aspirants get INT boosted to 9 if rolled lower (Lightblessed-specific ability floor); cleric-intent aspirants get WIS boosted to 9 if rolled lower. After exactly **4 months** (joined_calendar_day + 120), each aspirant makes a single proficiency throw of 14+ adding the relevant ability modifier (INT for mage intent, WIS for cleric intent). On success: promoted to 1st-level of intended class. On failure: leaves the sanctum (status='failed_promotion'). There is **no monthly attrition**; the promotion throw is the sole attrition check. The prior 1d6/month-for-6-months mechanic from O-D5 + earlier Q2 wording is fully scrapped. Schema: aspirants live in the `followers` table with source_kind='aspirant', character_class='normal_man', level=0, intended_class set, status='aspirant_in_training', promotion_eligible_day = joined_calendar_day + 120.

- **Q14.** **Garrison Training is NOT a class bucket — it's a proficiency-gated activity.** Manual of Arms (with combinable Riding / Weapon Focus enabling different troop types) is the canonical gate per RAW (with possible equivalent class powers TBD per Q14a). The `garrison_training` bucket is removed from `ClassBucketResolver`; troop training (`train_troops`, `oversee_troop_training`, `inspect_troops`) moves to the **Garrison sub-tab (§8)** with proficiency-based eligibility. Bardic Patronage promotes from a "variant of garrison_training" to its **own bucket** (`bardic_patronage`), surfaces ONLY for Bards, and only contains the Bard-specific class powers (Chronicles of Battle aura + Solicit Followers). The Syndicate detection rule also pivots from a combat_progression gate to a **class-id allowlist** matching RAW (`thief`, `assassin`, `elven_nightblade`) — this correctly handles Assassin (who has fighter combat-progression in the JSON but is hijink-eligible per RAW).

- **Q14a — OPEN follow-up:** Which specific `class_powers` in the project's class JSON files count as "Manual of Arms equivalent"? Current default: NONE — every class must take the Manual of Arms proficiency via normal proficiency progression. If any class powers (e.g., Fighter's `battlefield_leadership`) should grant training eligibility automatically, please specify.

---

## Phase 10A.1 — Sub-tab shell + ClassBucketResolver

### What it produces
The Class-Specific sub-tab appears in the Domain tab strip (replacing the current placeholder), shows correctly-labelled tab title per the active entity's class, and renders an empty stacked-block container for entities whose class has applicable buckets. No actual block content yet — all sub-tabs return "Block coming in 10A.2 / 10A.3 / 10B.x" placeholder cards.

### New files
- **`engine/subsystems/domains/class_bucket_resolver.gd`** — pure-function class-bucket detection. Public API:
  ```
  static func buckets_for(character_id: String) -> Array[String]
      # returns ordered array drawn from ["faith", "magical_research",
      # "trade", "syndicate", "garrison_training"]; empty array means no
      # Class-Specific tab for this entity
  static func primary_bucket_for(character_id: String) -> String
      # for stacked-block ordering: returns the bucket whose card should be
      # expanded by default; "" if no buckets
  static func sub_tab_label_for(character_id: String) -> String
      # "Class Activities" if multi-bucket; bucket display name if single;
      # "Bardic Patronage" for bards (Q3)
  ```
- **Detection rules** (RAW-grounded; tested against the §12.1 matrix):
  - **faith** ← `class_powers` contains `divine_casting` OR `spell_research_and_minor_item_creation` (covers Bladedancer's restricted divine casting)
  - **magical_research** ← `class_powers` contains `arcane_casting` OR (`spell_research` AND `combat_progression == "mage"`)
  - **trade** ← `class_powers` contains `stronghold_guildhouse` (Venturer)
  - **syndicate** ← `class_powers` contains `stronghold_hideout` AND `combat_progression == "thief"` (Thief / Assassin / Elven Nightblade — explicitly excludes Bard, who has `stronghold_hall` not `stronghold_hideout`)
  - **garrison_training** ← (`combat_progression == "fighter"` AND `level >= 5`) OR `class_id == "bard"` (Q3 — bard variant uses different content but same bucket key)
- **Primary-bucket ordering for stacked classes:**
  - Lightblessed Wonderworker: primary = `magical_research` (mage-rooted per Q2), Faith collapsed
  - Bladedancer: primary = `faith` (the divine focus is the class's flavor lead)
  - Anti-Paladin / Darkblood Ruinguard: primary = `garrison_training` (combat lead)
  - Elven Spellsword: primary = `garrison_training` (combat lead)
  - Elven Nightblade: primary = `syndicate`
- **`tests/test_class_bucket_resolver.gd`** — exhaustive matrix test, 1 test row per §12.1 entry (28 classes × 5 buckets = 140 assertions max).

### Modify
- **`scenes/ui/notebook/tab_pages/domain_tab_page.gd`** lines 64-66:
  - Replace the `class_specific` placeholder entry's `script` from `"placeholder"` to `"class_specific"`.
  - Add visibility logic in `_build_sub_tab_bar()` and `_ensure_sub_tab_page()`: when `ClassBucketResolver.buckets_for(active_entity_id)` is empty, **the tab is not added to the TabBar at all** per [generation/gdd-domain-tab.md:178](generation/gdd-domain-tab.md:178) §4.4 ("the strip renders eight sub-tabs in that case rather than rendering a placeholder").
  - Tab label is dynamic: `ClassBucketResolver.sub_tab_label_for(entity_id)` resolves to the correct title every time the active entity changes.
- **`scenes/ui/notebook/domain/sub_tabs/class_specific_sub_tab.gd`** (new) — block dispatcher:
  - On `display(domain)`: query `ClassBucketResolver.buckets_for(domain.owner_character_id)`, then for each bucket id, instantiate the corresponding `*_block.gd` and add as a `CollapsibleContainer` (consistent with existing collapsible-card pattern in the codebase — verify which one is canonical during implementation).
  - Primary bucket card starts expanded; others start collapsed.
  - Persists per-entity-per-block collapse state in `NotebookState` substate under `class_specific.collapse_state[entity_id][bucket_id]`.

### GDD updates (folded into this sub-phase per Q1-Q3)
- **`generation/gdd-domain-tab.md` §12.1 matrix** ([line 708](generation/gdd-domain-tab.md:708)): rename "Nobiran Wonderworker" row to "Lightblessed Wonderworker"; update notes column to reference Q2-resolution stacked-block model.
- **`generation/gdd-domain-tab.md` §12.7** ([line 804](generation/gdd-domain-tab.md:804)): rename heading to "Lightblessed Wonderworker hybrid block (per Q5/Q2 resolutions)"; rewrite the body to reflect:
  - 50/50 split at sanctum founding (NOT INT-vs-WIS dynamic)
  - 1d6/month-per-aspirant attrition for first 6 months (project-designed; RAW silent on rate)
  - Stacked-block model (Magical Research primary, Faith secondary collapsed)
- **`generation/gdd-domain-tab.md` §12.6** ([line 792](generation/gdd-domain-tab.md:792)): clarify that the "Bardic Patronage" variant of Garrison Training surfaces ONLY `hireling_inspiration` aura + `hall` recruitment (NOT `oversee_troop_training` / `train_troops`); cite [rules/ax_campaign_play.xml:678](rules/ax_campaign_play.xml:678) and [rules/acore_campaign_classes.xml:569-584](rules/acore_campaign_classes.xml:569).
- **`generation/gdd-domain-tab.md` §4.4** ([line 184](generation/gdd-domain-tab.md:184)): update bucket list bullets to use "Lightblessed Wonderworker"; clarify Bard parenthetical.

### Coding-conventions update
- Append new section to `docs/coding_conventions.md` establishing `ClassBucketResolver` as the **single source of truth** for class-bucket lookup. Forbid ad-hoc class-id checks for bucket purposes elsewhere in the codebase. Pattern: "If you find yourself writing `if class_id in [\"cleric\", \"bladedancer\", ...]:` somewhere, you're doing it wrong — call `ClassBucketResolver.has_bucket(character_id, \"faith\")` instead."

### Tests for 10A.1
- `tests/test_class_bucket_resolver.gd` — matrix coverage (one assertion per §12.1 row × bucket).
- `tests/test_class_specific_sub_tab_visibility.gd` — sub-tab present for cleric, hidden for L1 fighter (no garrison training yet), present for L5+ fighter, present for bard at any level (Q3), present for venturer.
- `tests/test_class_specific_sub_tab_label.gd` — pure mage label is "Magical Research"; Bladedancer label is "Class Activities"; Bard label is "Bardic Patronage"; Lightblessed label is "Class Activities".

---

## Phase 10A.2 — Faith block

### Schema (new migration `091_faith_block.sql`)
```sql
-- Per-domain congregant tracking. Cleric/bladedancer/etc. divine casters who
-- rule a domain are the "owner" of that domain's congregation; the relationship
-- is via domains.owner_character_id, so congregants are keyed per-domain.
-- For wandering divine casters without a domain, congregants are tracked on
-- the character via a separate row keyed character_id (NULL domain_id).
CREATE TABLE IF NOT EXISTS congregants (
    id                            TEXT    PRIMARY KEY,
    domain_id                     TEXT    REFERENCES domains(id),
    character_id                  TEXT    REFERENCES characters(id),
    count                         INTEGER NOT NULL DEFAULT 0,
    monthly_growth_pending_gp     INTEGER NOT NULL DEFAULT 0,
    last_resolved_calendar_day    INTEGER NOT NULL DEFAULT 0,
    created_at                    TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                    TEXT    NOT NULL DEFAULT (datetime('now')),
    CHECK ((domain_id IS NOT NULL) OR (character_id IS NOT NULL))
);
CREATE INDEX idx_congregants_domain_id  ON congregants(domain_id);
CREATE INDEX idx_congregants_character_id ON congregants(character_id);

-- Per-character divine power balance + weekly extraction cooldown anchor.
CREATE TABLE IF NOT EXISTS character_divine_power (
    character_id                  TEXT    PRIMARY KEY REFERENCES characters(id),
    divine_power_gp               INTEGER NOT NULL DEFAULT 0,
    last_extraction_calendar_day  INTEGER NOT NULL DEFAULT 0,
    created_at                    TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                    TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Consecration projects + completed altars.
CREATE TABLE IF NOT EXISTS consecrated_altars (
    id                       TEXT    PRIMARY KEY,
    character_id             TEXT    NOT NULL REFERENCES characters(id),
    location_kind            TEXT    NOT NULL DEFAULT 'stronghold'
        CHECK(location_kind IN ('stronghold', 'settlement_poi', 'wilderness_hex', 'dungeon_room')),
    location_ref             TEXT    NOT NULL DEFAULT '',
    gp_invested              INTEGER NOT NULL DEFAULT 0,
    alignment                TEXT    NOT NULL DEFAULT 'lawful'
        CHECK(alignment IN ('lawful', 'neutral', 'chaotic')),
    aura_size_sq_ft          INTEGER NOT NULL DEFAULT 0,  -- = gp_invested per 100 * 100 sq ft
    completion_pct           INTEGER NOT NULL DEFAULT 0,
    status                   TEXT    NOT NULL DEFAULT 'in_progress'
        CHECK(status IN ('in_progress', 'completed', 'broken_unblessed')),
    started_calendar_day     INTEGER NOT NULL DEFAULT 0,
    completed_calendar_day   INTEGER,
    created_at               TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_consecrated_altars_character ON consecrated_altars(character_id);

-- Pending divine effects: queue of resolutions that fire at applies_at_calendar_day.
CREATE TABLE IF NOT EXISTS pending_divine_effects (
    id                       TEXT    PRIMARY KEY,
    domain_id                TEXT    NOT NULL REFERENCES domains(id),
    character_id             TEXT    REFERENCES characters(id),
    effect_kind              TEXT    NOT NULL
        CHECK(effect_kind IN (
            'consecrate_fields_land_value',
            'consecrate_ruler_buff',
            'missionary_growth_carry',
            'tax_morale_modifier'
        )),
    effect_payload_json      TEXT    NOT NULL DEFAULT '{}',
    issued_calendar_day      INTEGER NOT NULL DEFAULT 0,
    applies_at_calendar_day  INTEGER NOT NULL DEFAULT 0,
    expires_at_calendar_day  INTEGER NOT NULL DEFAULT 0,
    status                   TEXT    NOT NULL DEFAULT 'pending'
        CHECK(status IN ('pending', 'applied', 'expired', 'cancelled')),
    created_at               TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_pending_divine_effects_apply
    ON pending_divine_effects(applies_at_calendar_day, status);
CREATE INDEX idx_pending_divine_effects_domain
    ON pending_divine_effects(domain_id);
```

### Data file (new)
- **`data/activities/divine_category.json`** — 8 activities verbatim from [rules/ax_campaign_play.xml:380-500](rules/ax_campaign_play.xml:380): `dispatch_missionaries`, `cast_charitable_spells`, `consecrate_altar`, `consecrate_fields`, `consecrate_ruler`, `extract_divine_power`, `perform_blood_sacrifice`, `perform_ceremonial_sacrifice`. Fields: `id`, `category="divine"`, `frequency`, `activity_level`, `strenuous`, `default_ticks_required`, `session_time_cost_rounds`, `location_kind`, `prerequisites` (e.g. `["divine_caster", "level_5_plus"]` for consecrate_altar), `alignment_restriction` (`"chaotic"` for blood sacrifice, `"lawful"` for ceremonial), `restricted_period_rounds` (1 day / 1 week / 1 month / 1 year per RAW), `effect_summary`, `raw_citation`.

### Engine handlers (8 new files in `engine/subsystems/activities/handlers/faith/`)
1. **`dispatch_missionaries.gd`** — Restricted (monthly cap). On launch: deducts the configured "missionary wages this month" gp from the ruler's domain treasury, accrues that gp into `congregants.monthly_growth_pending_gp`. Effect resolves on monthly tick.
2. **`cast_charitable_spells.gd`** — Singular minor. Player picks one or more daily-cast spell rows; handler computes total spell-cost gp from the Spell Availability by Market table (lookup via `SpellRegistry`'s existing cost helper); accrues into `congregants.monthly_growth_pending_gp`.
3. **`consecrate_altar.gd`** — Ongoing (`session_time_cost_rounds = day`, `ticks_required = ceil(gp_committed / 500)`). On launch: INSERTs `consecrated_altars` row with `status='in_progress'`. On completion: marks `status='completed'`, `aura_size_sq_ft = (gp_invested / 100) * 100`. Emits `EventBus.altar_consecrated`. **Allows DP substitution per [rules/ax_campaign_play.xml:419](rules/ax_campaign_play.xml:419)** — gp can come from `character_divine_power` if player elects (param: `dp_share_pct`).
4. **`consecrate_fields.gd`** — Ongoing (`ticks_required = ceil(peasant_families / 780)`). On completion: deducts `2 * peasant_families` from `character_divine_power`; rolls magic-research throw (target from [rules/acore-campaign-general-and-magic-research.xml:25-51](rules/acore-campaign-general-and-magic-research.xml:25)); on success enqueues `pending_divine_effects` row (`effect_kind='consecrate_fields_land_value'`, `applies_at = next_monthly_tick_day`, `payload={delta_gp_per_family: +1, peasant_families: N}`); on natural 1, payload delta is −1.
5. **`consecrate_ruler.gd`** — Restricted (yearly cap). Deducts `monthly_revenue_gp` from `character_divine_power`. Magic-research throw. On success enqueues 12-month `pending_divine_effects` row (`effect_kind='consecrate_ruler_buff'`, applies for next 12 monthly ticks: +1 base morale, +1 vassal loyalty, double-vagary roll). On natural 1: −1 base morale, −1 vassal loyalty, worse-of-two-vagaries.
6. **`extract_divine_power.gd`** — Restricted (weekly cap). Deposits `floor(congregants/5) * 10` gp + `roll(0..8) * floor(peasant_families/10)` if domain ruler/spiritual advisor (additive). Updates `last_extraction_calendar_day`. Emits `divine_power_changed`.
7. **`perform_blood_sacrifice.gd`** — Restricted (daily cap), Chaotic only. Param `sacrifice_target_id` (creature row from a "captured for sacrifice" inventory the cleric maintains — Phase 10A.2 scope: just look up XP value via `MonsterRegistry` or character XP). Multiplies by `min(class_level, n_sacrifices_per_session)` per the per-class-level rule. Deposits into `character_divine_power`.
8. **`perform_ceremonial_sacrifice.gd`** — Restricted (daily cap), Lawful only. Tracks gp value of ceremonial expenditures into `congregants.monthly_growth_pending_gp`.

Plus **`faith_handlers_registration.gd`** that registers all 8 with `ActivityHandlerRegistry`.

### Monthly-tick integration
Extend `engine/subsystems/session/handlers/domain_handlers.gd` `_resolve_domain_month` with a new step: **resolve faith-bucket monthly events**. Order:
1. **Resolve pending divine effects** — flush `pending_divine_effects` rows whose `applies_at_calendar_day == today`. For `consecrate_fields_land_value`: bump that month's land-value-revenue calculation by the payload delta. For `consecrate_ruler_buff`: apply +1 morale base / +1 vassal-loyalty roll modifier / vagary doubling for this monthly tick.
2. **Resolve congregant growth** — for each domain-with-faith-bucket-ruler: if `monthly_growth_pending_gp >= 1000`, roll `1d10 + cha_mod` per 1,000 gp; add to `congregants.count`. Reset `monthly_growth_pending_gp = monthly_growth_pending_gp mod 1000`. Per [rules/ax_campaign_play.xml:20-22](rules/ax_campaign_play.xml:20).
3. **Resolve congregant upkeep** — 1 gp/congregant/month. Source-of-funds order: deduct from `character_divine_power.divine_power_gp` first (since RAW says DP can fund church operations), then from `domains.treasury_gp`. If unpaid: `1d10` congregants depart per `1,000 gp` unpaid per [rules/ax_campaign_play.xml:109-112](rules/ax_campaign_play.xml:109).

### EventBus signals (additions to `engine/autoloads/event_bus.gd`)
- `congregants_changed(character_id, new_count, delta)`
- `divine_power_changed(character_id, new_total, delta)`
- `altar_consecrated(altar_id, character_id, gp_invested)`
- `consecrate_fields_resolved(domain_id, success: bool, land_value_delta_per_family: int)`
- `consecrate_ruler_resolved(domain_id, ruler_character_id, success: bool, expires_at_day: int)`
- `missionary_dispatch_recorded(domain_id, gp_committed)`

### UI
- **`scenes/ui/notebook/domain/blocks/faith_block.gd`** — collapsible card per [generation/gdd-domain-tab.md:714](generation/gdd-domain-tab.md:714) §12.2:
  - Header row: Congregants count + projected next-month growth ("142 congregants · +12 expected next month from 4,500 gp pending")
  - Divine Power tracker: current balance, this-week extraction status (greyed if cooldown not yet elapsed), button to launch `extract_divine_power`
  - Altar list: each `consecrated_altars` row as a sub-card (gp invested, aura size, alignment, location); in-progress consecrations show progress bar
  - Pending divine effects: small banner showing any active `consecrate_ruler_buff` countdown, etc.
  - Activity launcher cards (8): use the same pattern as `decrees_and_remote_orders_sub_tab.gd`'s decree cards. Location-gated per [generation/gdd-domain-tab.md:732](generation/gdd-domain-tab.md:732) (greyed out with travel-shortcut affordance when player is not in the right place).
  - Religious authority section (visible only when active entity rules a domain): cross-link to Overview's religion editor; surfaces religious-conversion penalties per `acore_axioms` §new_religion.

### Tests for 10A.2
- `tests/test_faith_dispatch_missionaries.gd`
- `tests/test_faith_cast_charitable_spells.gd`
- `tests/test_faith_consecrate_altar.gd`
- `tests/test_faith_consecrate_fields.gd` — land-value bump on next tick + natural-1 negative case
- `tests/test_faith_consecrate_ruler.gd` — 12-month buff window, yearly cooldown
- `tests/test_faith_extract_divine_power.gd` — weekly cooldown, congregants/5×10 math, +0..8 per 10 fam ruler bonus
- `tests/test_faith_perform_blood_sacrifice.gd` — chaotic-only gate, DP = creature XP × n
- `tests/test_faith_perform_ceremonial_sacrifice.gd` — lawful-only gate, gp accumulator
- `tests/test_faith_monthly_congregant_resolution.gd` — end-to-end: 4,500 gp → 4 × (1d10+cha_mod) growth, pending_gp resets to 500
- `tests/test_faith_monthly_congregant_upkeep_unpaid.gd` — 1 gp/congregant unpaid → 1d10 depart per 1k unpaid
- `tests/test_faith_block_visibility.gd` — block renders only for divine-bucket classes

---

## Phase 10A.3 — Bardic Patronage class-bucket + Garrison sub-tab proficiency-gated training launchers

**Per Q14 [RESOLVED 2026-05-11], this sub-phase has been re-architected.** Garrison Training is no longer a class bucket; it's a proficiency-gated activity that surfaces in the Garrison sub-tab. Bardic Patronage promotes to its own class bucket for Bards only. This sub-phase ships BOTH surfaces in one wave (they share the underlying troop-training handlers).

### What it produces

1. **Bardic Patronage class-bucket block** (Class-Specific sub-tab, Bards only). Two RAW-grounded surfaces:
   - Chronicles of Battle aura status (passive +1 morale aura on hirelings/mercenaries when bard is present)
   - Solicit Followers launcher (Ongoing 1-3 weeks, L9+, recruits 1d4+1×10 0-level mercenaries + 1d6 1st-3rd-level bards)

2. **Garrison sub-tab training launchers** (Garrison sub-tab, §8.2 — eligibility-gated on Manual of Arms proficiency). Three RAW activities:
   - `train_troops` (major ongoing; Manual of Arms rank 1+ for light infantry, rank 2 for heavy infantry, combinable with Riding/Weapon Focus for other troop types per the RAW table)
   - `oversee_troop_training` (minor ongoing; ruler-of-domain — RAW text says "fighter attack progression L5+" but per Q14 we treat this as the noble-overseer angle and broaden it; pending Q14a refinement)
   - `inspect_troops` (minor singular; ruler-of-domain)

### No new schema
Reuses `troop_units` (Phase 5), `henchmen` (existing). Proficiency state is queried via the existing proficiency registry/repository.

### Engine — flesh out existing handlers (proficiency-gated)
- **`engine/subsystems/activities/handlers/train_troops.gd`** (exists; complete it):
  - **Eligibility:** Manual of Arms proficiency rank 1+ on the launching character. Companion proficiencies (Riding, Weapon Focus (bows & crossbows)) unlock additional troop types per the Manual of Arms RAW table:
    | Troop type | Required proficiencies | Training duration |
    |---|---|---|
    | Light infantry | Manual of Arms rank 1 | 1 month |
    | Heavy infantry | Manual of Arms rank 2 | 1 month |
    | Light cavalry | Manual of Arms rank 1 + Riding | 3 months |
    | Heavy cavalry | Manual of Arms rank 2 + Riding | 6 months |
    | Crossbowmen | Manual of Arms rank 1 + Weapon Focus (bows & crossbows) | 1 month |
    | Bowmen | Manual of Arms rank 1 + Weapon Focus (bows & crossbows) | 2 months |
    | Longbowmen | Manual of Arms rank 1 + Weapon Focus (bows & crossbows) | 3 months |
    | Horse archers | Manual of Arms rank 1 + Riding + Weapon Focus | 6 months |
    | Cataphract cavalry | Manual of Arms rank 2 + Riding + Weapon Focus | 12 months |
  - Cap: 60 soldiers per training period.
  - Earnings per RAW: 30gp/month with rank 1, 60gp/month with rank 2 (added to the trainer's coin, NOT the domain treasury per RAW phrasing).
  - On completion: mark assigned `troop_units` as `tier = "veteran"` (or transition `untrained → average → veteran` per the existing Phase 5 tier model), recompute `battle_rating`.
- **`engine/subsystems/activities/handlers/oversee_troop_training.gd`** (exists; complete it):
  - **Eligibility:** ruler-of-domain. Per Q14, the prior fighter-attack-progression gate is dropped; this activity is now broadly available to any ruler. RAW text retained as a note. Pending Q14a clarification on whether this should require Manual of Arms too.
  - One ongoing minor activity per 60 troops.
  - On completion: grant +1 permanent morale to the overseen troop_units.
- **`engine/subsystems/activities/handlers/inspect_troops.gd`** (exists; complete it):
  - Singular minor. Eligibility: ruler-of-domain.
  - On completion: temporary +1 morale on the next combat-morale roll for the inspected unit.

### Engine — new Bardic handlers (`engine/subsystems/activities/handlers/bardic/`)
- **`solicit_followers.gd`** — Ongoing 1-3 weeks (mirrors solicit_mercenaries cadence). On completion: insert `1d4+1` × 10 0-level mercenary `troop_units` (source_type = `mercenary`, troop_type = `light_infantry` default), AND 1d6 1st-3rd-level bard henchmen via existing `henchman_lifecycle_manager`. Player can decline-to-hire; hire requires standard mercenary wages. Eligibility: Bard class_id, L9+.
- **`chronicles_of_battle_aura.gd`** — passive system (NOT an activity launchable by the player). Listens for `combat_started` and morale-roll signals; if a bard at L5+ is in the same hex/army as the rolling unit and the unit is a hireling/mercenary of the bard, applies +1 to the morale roll. Stacks with Charisma/proficiency mods per [rules/acore_campaign_classes.xml:572-573](rules/acore_campaign_classes.xml:572).

### Data file (new)
- **`data/activities/bardic_category.json`** — 1 launchable activity entry (`solicit_followers`) + a documentation-only entry for `chronicles_of_battle` (passive ability).

### EventBus signals (additions)
- `troop_training_completed(troop_unit_id, morale_delta)` (triggered by oversee_troop_training)
- `troop_unit_tier_advanced(troop_unit_id, new_tier)` (triggered by train_troops; replaces the prior `troop_veteran_promoted`)
- `bard_followers_solicited(character_id, mercenaries_count, bards_count)`
- `chronicles_of_battle_aura_applied(bard_character_id, target_unit_id, morale_modifier)` — for log surfacing

### UI
- **`scenes/ui/notebook/domain/blocks/bardic_patronage_block.gd`** (new; replaces the planned `garrison_training_block.gd`) — collapsible card per `gdd-domain-tab.md` §12.6 (the new §12.6 per Q14):
  - Chronicles of Battle aura status section
  - Solicit Followers launcher card (greyed when Bard < L9)
  - Recruitment history (last solicitation outcomes)
- **Garrison sub-tab §8.2 "Training" sub-section** (new; in `scenes/ui/notebook/domain/sub_tabs/garrison_sub_tab.gd` — extending the existing Phase 5 sub-tab):
  - Training queue (in-progress projects with progress bars + completion timeline + eligibility readouts)
  - Activity launcher cards: `train_troops` (with per-troop-type radio buttons gated on proficiency/companion-proficiency presence), `oversee_troop_training`, `inspect_troops`
  - Per-troop-type eligibility table showing the active entity's current authorizations
  - Greyed-out launchers with tooltips when proficiency requirements aren't met (e.g., "Requires Manual of Arms rank 1+")

### Tests for 10A.3
- `tests/test_train_troops_proficiency_eligibility.gd` — Manual of Arms rank 1 character can launch light infantry training; rank 2 can launch heavy infantry; rank 1 + Riding can launch light cavalry; rank 1 + Weapon Focus can launch bowmen; etc. Character WITHOUT Manual of Arms cannot launch any train_troops project.
- `tests/test_train_troops_completion_tier_advance.gd` — 1-month light infantry project on assigned untrained troop_units → on completion units are at `average` tier with recomputed BR.
- `tests/test_oversee_troop_training_completion.gd` — ruler oversees a 60-troop unit; on completion, unit gets +1 permanent morale.
- `tests/test_inspect_troops.gd` — singular minor; emits next-combat-round morale buff signal.
- `tests/test_bardic_solicit_followers.gd` — Ongoing 1-3 weeks; on completion, dice math correctly inserts 0-level mercenary troop_units + 1st-3rd-level bard henchmen.
- `tests/test_bardic_chronicles_of_battle_aura.gd` — bard in same hex as army → +1 morale on mercenary morale rolls; bard absent → no aura.

---

## Phase 10B.1 — Magical Research block

### Depends on
Settles independently from 10B.2/10B.3 except for Lightblessed Wonderworker stacking with Faith block (10A.2).

### Schema (new migration `092_magical_research.sql`)
- `magic_research_projects(id, character_id, project_kind, target_spell_key, target_spell_level, target_item_kind, gp_committed, days_total, days_completed, target_value, library_id, workshop_id, status, started_calendar_day, completed_calendar_day, params_json)`
- `libraries(id, owner_character_id, location_kind, location_ref, gp_invested, max_spell_level_supported, magic_research_throw_bonus, status)`
- `workshops(id, owner_character_id, location_kind, location_ref, gp_invested, max_spell_level_supported, magic_research_throw_bonus, status)`
- `apprentices(id, owner_character_id, sanctum_id, character_id_if_named, level, intelligence, status, joined_calendar_day)` — for mage / Lightblessed apprentices that have made it past aspirant
- `wonderworker_aspirants(id, owner_character_id, sanctum_id, intended_class, months_since_arrival, status)` — for Lightblessed 0-level aspirants under the 1d6/month-for-6-months attrition (Q2)

### Activities
- `research_magic`, `rewrite_spell`, `replace_spell`, `scribe_spell`, `manage_assistant` per [rules/ax_campaign_play.xml:732-792](rules/ax_campaign_play.xml:732)
- For Lightblessed: research-project picker MUST allow targets on EITHER arcane spell list OR cleric divine spell list (per Q2 / roadmap RESOLVED).

### Mage's dungeon-under-tower hook (Q9 shortcut)
- Magical Research block displays existing-dungeon status for mage rulers (read-side: count of `dungeon_entrances` rows where `mage_owner_character_id == active_entity_id`, summary of monsters lured)
- Hook into Phase 9A's `domain_encounter_resolver`: dungeon presence in domain increases encounter frequency by a flat modifier (project-designed, NOT full RAW dungeon-stocking). **Build log MUST document:** "Phase 10B.1 dungeon-under-tower hook is a flat encounter-frequency multiplier; full dungeon-stocking-with-monsters per [rules/acore-campaign-hijinks.xml:545-611](rules/acore-campaign-hijinks.xml:545) is deferred to dedicated dungeon-system phase. Re-wire when dungeon-system ships."

### Lightblessed Wonderworker integration
- Stacked-block: Magical Research expanded, Faith collapsed by default.
- 50/50 follower split at sanctum founding (player can rebalance via UI control on the sanctum-founding flow — needs a `wonderworker_split_pct` param on stronghold completion, default 50).
- Aspirant promotion (per Q20 [RESOLVED 2026-05-11]): each aspirant row in `followers` (source_kind='aspirant') gets `promotion_eligible_day = joined_calendar_day + 120` (4 months × 30 days). On that day, the monthly-tick resolver fires a single d20 + ability_mod throw (INT for mage intent, WIS for cleric intent). 14+ promotes to 1st-level mage/cleric (sets character_class, level=1, status='present'); 13 or less sets status='failed_promotion', departed_day. **No monthly attrition.**
- Mage-intent aspirants get INT floor of 9 (boosted at creation if rolled lower); cleric-intent aspirants get WIS floor of 9. Both ability floors are Lightblessed-specific; standard Mage sanctums don't apply them.
- Stacks `[magical_research, faith]` buckets per Q11; the magic_research_projects row's research-target picker for Lightblessed accepts targets on EITHER arcane OR cleric divine spell list (filter wiring lands in 10B.1g).

---

## Phase 10B.2 — Trade block (Venturer)

### Depends on
- The parallel Phase 10B-prerequisite session must land:
  - Common Merchandise + Precious Merchandise registries with base prices and load weights
  - `MarketPriceResolver` for the 4d4 + demand modifier procedure
  - Per-settlement merchant pool (so `solicit_merchants` can produce correct counts)
- Q5: full implementation, not v1 stub.

### Schema (new migration `093_trade_block.sql`)
- `monopoly_holdings(id, venturer_character_id, settlement_entrance_id, claimed_calendar_day, monthly_revenue_gp, status)`
- `venturer_apprentices(id, owner_character_id, guildhouse_id, level, status, joined_calendar_day)` — 2d6 1st-level apprentices on guildhouse completion per [rules/ax_venturer_class.xml:193-201](rules/ax_venturer_class.xml:193)

### Activities
- All `<category name="mercantile">` activities from [rules/ax_campaign_play.xml:795-1001](rules/ax_campaign_play.xml:795) — buy_sell_*, commission_*, enter_market, hire_hirelings, persuade_*, solicit_*

### Monthly tick integration
- For each `monopoly_holdings` row: ledger entry `category=revenue, subcategory=monopoly_revenue, gp_amount = settlement.urban_families * 1`. Per [rules/ax_venturer_class.xml:207](rules/ax_venturer_class.xml:207).

---

## Phase 10B.3 — Syndicate block

### Depends on
- Same parallel session prerequisites as 10B.2 (merchandise registry for smuggling/stealing payouts)
- Q6: full Crime & Punishment resolver
- Q8: per-hijink resolution for PC syndicates; simplified-table fast path for NPC-only syndicates

### Schema (new migration `094_syndicate_block.sql`)
- `hijink_assignments(id, syndicate_member_id, boss_character_id, hideout_id, hijink_kind, planning_state, planning_days_required, planning_days_completed, status, started_day, completed_day, target_id, throw_result, gp_yield, caught: bool)`
- `caught_perpetrators(id, character_id, crime_type, time_languishing_days, attorney_rank, bribe_amount_gp, interpleader_id, verdict, fine_gp, punishment_kind, punishment_resolved: bool, prior_crimes_modifier)`
- `syndicates(id, boss_character_id, hideout_stronghold_id, base_settlement_id, syndicate_size_max, current_size, status)` — captures hideout_size_and_cost table from [rules/acore-campaign-hijinks.xml:30-45](rules/acore-campaign-hijinks.xml:30)
- `syndicate_members(id, syndicate_id, character_id_if_named, level, follower_kind, status, hijink_eligible: bool)` — for the bulk of unnamed members
- `lay_low_state(id, character_id, base_id, started_day, ends_day)` — tracks 2d8+3 days laying low per RAW

### Activities
- All `<category name="syndicate">` activities from [rules/ax_campaign_play.xml:1127-1252](rules/ax_campaign_play.xml:1127): order_hijink, plan_hijink, perform_hijink, lay_low, await_trial, bribe_magistrate, hire_attorney, interplead

### Per-hijink resolvers (Q5/Q8)
- One handler module per hijink kind: `assassinating.gd`, `carousing.gd`, `smuggling.gd`, `spying.gd`, `stealing.gd`, `treasure_hunting.gd`. Each implements the full RAW resolution from [rules/acore-campaign-hijinks.xml:102-237](rules/acore-campaign-hijinks.xml:102):
  - Eligibility check (assassins+nightblades only for assassinating; thieves only for stealing/smuggling/treasure-hunting; etc.)
  - Proficiency throw with appropriate skill (Hide in Shadows / Hear Noise / Move Silently / Pick Pockets / Find Traps)
  - Success → roll yield (uses the merchandise / market-price resolver from the prereq session)
  - Failure-by-14+ or natural 1 → `caught_perpetrators` row (charges from the per-hijink charges_on_capture table)
- Smuggling/stealing payout: aggregate gp via merchandise table (Q5: full resolver, dependent on prereq session)
- For NPC-only syndicates: a `npc_syndicate_monthly_resolver.gd` uses the simplified `monthly_hijink_income_table` ([rules/acore-campaign-hijinks.xml:501-518](rules/acore-campaign-hijinks.xml:501)) as a perf shortcut (Q8). Per-syndicate-member level → flat monthly gp; the table "already factors in wages, attorneys, bribes, fines, and healing" so no caught-perpetrator generation for NPCs. PC-controlled syndicate members (and any L9+ member) always roll per-hijink.

### Crime & Punishment resolver (Q6)
- `engine/subsystems/syndicate/crime_and_punishment_resolver.gd`:
  - Inputs: `caught_perpetrators` row + character state (Charisma, proficiencies, prior_crimes count) + active modifiers (attorney_rank, bribe_amount, interpleader)
  - Procedure: 2d6 + Cha + Profession(attorney) + bribery + evidence (1d4 favorable / 1d8 unfavorable) + interpleader + prior_crimes + severity → Crime & Punishment table verdict
  - Verdict effects:
    - **Mechanically applied:** fines (deduct from character or syndicate-boss treasury), prison time (block character actions for time_languishing_by_crime period)
    - **Logged but not mutated in v1:** brandings (-1 reaction), maimings (-2 reaction, can't speak), permanent wounds, executions/proscriptions. Each becomes a `presentation` log entry but does not write to character state. **MUST be documented in build_log.md as a v1-shortcut to be re-wired when permanent-character-effects system lands.**

---

## Where this plan is anchored
- This file: `docs/phase-10-plan.md`
- Q5 deliverable (subsystem dependencies for parallel session): `docs/phase-10b-subsystem-dependencies.md`
- Roadmap source: `docs/domain-roadmap-corrected.md` Phase 10 (line 411+)
- GDD source: `generation/gdd-domain-tab.md` §12 (with §12.7 + §12.6 + §12.1 to be updated in 10A.1 per Q1-Q3)
- RAW sources cited inline above
