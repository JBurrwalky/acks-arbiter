# GDD: Religion Conversion

**Document type:** Game Design Document (project-designed, modifiable)
**Authority:** PROJECT-DESIGNED — RAW provides the anchors but the timeline, cost curve, and morale gating are project decisions. Subordinate to `docs/acks_arbiter_design_brief_v11.md` and to [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §8 (conquest-time alignment transition v1 default).
**Status:** Draft v1.1 — Q-RC-1 / 2 / 3 / 4 / 5 / 6 / 7 / 8 resolved 2026-05-20; v1.0 anti-paladin example corrected (Paladins/Anti-Paladins are NOT divine casters per ACKS — they're religious-zealot Fighters); heresy/excommunication subsystem removed; alignment-shift threshold reframed as 60% of population in new religion's congregation rather than an abstract `progress_pct`; urban-growth-stocking system flagged as a deferred project-wide dependency.
**Depends on ACKS rules:**
- `rules/acore_axioms_strongholds_and_domains.xml:245` ("Changing religion is possible but causes severe morale penalties" — the explicit anchor that conversion exists);
- `rules/acore_axioms_strongholds_and_domains.xml:471` ("Changing religion changes the effective domain alignment only under the conversion rules described below" — religion change IS alignment change);
- `rules/acore_axioms_strongholds_and_domains.xml:466` ("A domain's apparent alignment is determined by religious practice" — religion is the alignment-determining attribute);
- `rules/acore_axioms_strongholds_and_domains.xml:467-470` (alignment-vs-religion morale penalty table — −1 / −2 ruler-vs-domain mismatch);
- `rules/acore-campaign-general-and-magic-research.xml:549-601` (full proselytizing + congregants procedure, including the Domain Worship table);
- `rules/ax_campaign_play.xml:18-22` (monthly congregant-growth phase: 1d10 + Cha bonus per 1,000gp proselytizing);
- `rules/ax_campaign_play.xml:384-408` (`dispatch_missionaries` + `cast_charitable_spells` Faith activities — already shipped in Phase 10A.2).
**Depends on project GDDs:**
- [`gdd-domain-tab.md`](gdd-domain-tab.md) §12.2 (Faith block — the existing class-specific surface this GDD extends); §11 (Decrees & Remote Orders — the non-divine-ruler decree surface);
- [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §8 (conquest-time transition v1 default — alignment stays until conversion completes); §9.6 (vassal-appointment warning copy references conversion timeline).
**Modifiable by Claude Code:** Yes within constraints. The conversion-as-congregant-acquisition model (§3) and the data shape (§4) are project-direction. Specific numbers — morale-curve coefficients, driver-bonus multipliers, the 60% completion threshold — are engineering decisions tunable from the values in §5.
**Last updated:** 2026-05-20

---

## 1. Purpose and Scope

This GDD specifies the project-designed mechanic for changing a domain's religion. ACKS RAW says religion can change but quotes only "severe morale penalties" as the consequence (`rules/acore_axioms_strongholds_and_domains.xml:245`); the actual timeline, cost, success/failure curve, and UI surface are project-designed. This document locks the v1 design.

Religion conversion is the **only mechanism in v1 that changes a domain's alignment**. Per [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §8.1, conquest does NOT flip alignment — the conquered domain retains its prior alignment indefinitely, with the −2 ruler-vs-domain morale penalty active, until conversion completes. Religion conversion is therefore the cost-and-time-bearing arc that resolves alignment mismatches a ruler accumulates through conquest, succession (heir of mismatched alignment), or any other ownership transfer between alignments.

**The core insight (from RAW):** congregants are the conversion-tracking primitive. Per `rules/acore-campaign-general-and-magic-research.xml:551-553`, congregants share the caster's alignment, deity, and spiritual-advisor relationship. A domain's religious practice (and therefore its alignment per `acore_axioms` L466) is *de facto* whatever religion the majority of its peasant population practices. Conversion = acquiring enough congregants in the new religion to flip the majority. The Faith block's `dispatch_missionaries` + `cast_charitable_spells` activities (shipped in Phase 10A.2) are the existing proselytizing inputs; religious-structure investment (consecrated altars, plus future urban-temple POIs per §9.8) is the third input. This GDD dovetails with that infrastructure rather than reinventing it.

**Out of scope** (referenced but specified elsewhere):

- The Faith block's per-activity mechanics — `gdd-domain-tab.md` §12.2 and the Phase 10A.2 build log.
- Style transitions (`civilized` ↔ `clanhold`) — those don't happen in v1 per [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §8.3.
- Heresy and excommunication mechanics — explicitly REMOVED from v1 per Q-RC-4 resolution. Deferred to Phase 12+ faction / cult conflict work. The legal-crime "Heresy" on Phase 10B.3's crime table is a separate concern (a court charge against an individual, not a domain-level theological event).
- Urban growth stocking — the systemic question of "how do urban settlements gain temples + clerics as they grow" is a deferred project-wide dependency, flagged in §9.8 as Q-RC-9.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **Religion changes are possible but costly** (`rules/acore_axioms_strongholds_and_domains.xml:245`): *"Changing religion is possible but causes severe morale penalties."* The cost magnitude and shape are project-designed; the existence of the mechanic is RAW.

- **Religion is the alignment-determining attribute** (`rules/acore_axioms_strongholds_and_domains.xml:466`): *"A domain's apparent alignment is determined by religious practice."* This means the conversion mechanic operates on `domains.effective_religion` (per §4) as its primary state variable; alignment is derived.

- **Religion change IS alignment change** (`rules/acore_axioms_strongholds_and_domains.xml:471`): *"Changing religion changes the effective domain alignment only under the conversion rules described below."* This is the project's mandate to specify those rules; this GDD is the "described below."

- **Alignment-vs-religion morale penalty table** (`rules/acore_axioms_strongholds_and_domains.xml:467-470`):
  - Lawful or Chaotic ruler in a Neutral domain: −1 base morale.
  - Neutral ruler in a Lawful or Chaotic domain: −1 base morale.
  - Lawful ruler in a Chaotic domain, or Chaotic ruler in a Lawful domain: −2 base morale.
  - These penalties apply continuously while ruler-vs-domain alignment mismatch persists. Conversion completion is the only mechanism to clear them.

- **Congregants are the canonical religion-tracking primitive** (`rules/acore-campaign-general-and-magic-research.xml:551-553`):
  - Congregants must share the caster's alignment.
  - Congregants must worship the caster's deity.
  - Congregants must regard the caster as their spiritual advisor.

- **Monthly proselytizing procedure** (`rules/acore-campaign-general-and-magic-research.xml:559-565` + `rules/ax_campaign_play.xml:18-22`):
  - Each month, total: (charitable spell gp value) + (missionary hireling wage gp) + (religious structure gp value erected in the realm).
  - Per full 1,000gp of proselytizing value: gain **1d10 + Cha bonus** congregants.
  - **Cap:** "The caster cannot gain more congregants than exist in the realm being proselytized."

- **Congregant maintenance** (`rules/acore-campaign-general-and-magic-research.xml:568-572`):
  - 1gp per congregant per month upkeep.
  - Unpaid maintenance → lose 1d10 congregants per 1,000gp unpaid, with exploding 10s.

- **Domain morale gates effective faith** (`rules/acore-campaign-general-and-magic-research.xml:577`): *"A ruler can command subjects to worship his god, but actual faith depends on domain morale."* The Domain Worship table (`rules/acore-campaign-general-and-magic-research.xml:580-595`) scales divine-power output by morale: −4 morale = 0 DP, +4 morale = 8 DP per 10 families per week. The same morale-gates-faith pattern governs conversion progress in this GDD (§5).

- **Spiritual advisor relationship** (`rules/acore-campaign-general-and-magic-research.xml:578`): *"To become a ruler's spiritual advisor, the divine spellcaster generally must be the highest-level divine spellcaster with whom the ruler has Friendly relations."* This becomes the eligibility gate for an NPC divine caster to serve as the conversion's "driving caster" when the ruler is not themselves a divine caster (§3.2).

- **Tithes link maintenance to religion failure modes (deferred)** (`rules/acore_axioms_strongholds_and_domains.xml:240-247`): unpaid tithes reduce loyalty and *"may trigger heresy or excommunication."* These RAW hooks are NOT operationalized in v1 per Q-RC-4 resolution; they wait for Phase 12+ faction work.

---

## 3. Project Design Stance: Conversion as Congregant Acquisition

Religion conversion in Arbiter is a **months-long arc tracked as accumulating congregants of the target religion in the target domain.** The arc has four phases:

1. **Declaration** — the domain's ruler issues a religion-change decree. `domains.religion` (the declared religion) updates immediately. A `domain_religion_conversion` row is created. The domain's `effective_religion` (the population's actual practice) stays as-is, and the domain's `alignment` (derived from effective religion) stays as-is. The −1 / −2 ruler-vs-domain alignment penalty from §2 kicks in if ruler alignment ≠ effective-religion alignment.

2. **Proselytization** — monthly, the Faith block's `dispatch_missionaries` + `cast_charitable_spells` + religious-structure investment accumulate proselytizing gp per `rules/acore-campaign-general-and-magic-research.xml:559-565`. The 1d10 + Cha bonus formula applies, capped per the RAW limit. New congregants are added to the per-character-per-domain congregants table (per §4).

3. **Progress accrual** — each month, congregants of the target religion in the target domain grow toward the **60% of peasant_families** threshold. Progress is modified by:
   - Domain morale (the morale gating curve per §5.3);
   - Presence/role of the driving caster (in-domain bonus; spiritual-advisor bonus);
   - Consecrated altars of the target religion in the domain.
   The arc is **slow by design** — months to years, not weeks.

4. **Completion** — when target-religion congregants in the domain reach **60% of peasant_families** (per Q-RC-7 resolution), `effective_religion` flips to the new religion atomically and `alignment` updates per `acore_axioms` L466. The conversion row is marked complete. The −1 / −2 ruler-vs-domain alignment penalty clears (assuming ruler matches the new religion's alignment).

The arc may **stall** (congregants accrue at 0× during low morale) without ever failing. The arc fails outright only via the §7 failure modes: catastrophic morale collapse sustained 3+ months, ruler death without succession aligning, or explicit player abort.

### 3.1 What conversion is NOT

- **Not instant.** Even a high-investment, high-morale conversion is at minimum a year.
- **Not free.** The ongoing proselytizing investment + congregant maintenance + the morale penalty during the arc are real costs.
- **Not silent.** Each meaningful threshold crossing writes a Departure Log entry per [`gdd-domain-tab.md`](gdd-domain-tab.md) §14.1 (`religion_converted` event_type already exists from Phase 11A).
- **Not coupled to style.** Religion conversion can fire on civilized-style and clanhold-style domains identically. (Clanholds can convert between chaotic deities, between chaotic and neutral, etc.; only the beastman-clanhold-locked-to-chaotic constraint in [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §3.2 prevents a beastman-populated clanhold from converting AWAY from chaotic alignment.)

### 3.2 Who drives conversion

**Divine spellcasters** (per ACKS RAW) include Cleric, Bladedancer, Priestess, Shaman, Dwarven Craftpriest, Lightblessed Wonderworker (Faith stack), Witch (where divine), and similar classes whose `class_powers` include `divine_casting`. **Paladins and Anti-Paladins are NOT divine casters in ACKS** — they are religiously-themed Fighter variants with class powers but no spell repertoire (see `memory/feedback_paladin_anti_paladin_not_divine_casters.md`). A Paladin or Anti-Paladin ruler driving religion conversion does so via secular missionary investment only, with no divine-driver bonus.

Three driver patterns at the conversion arc:

- **Divine-caster ruler (cleric / bladedancer / etc.).** Ruler IS a divine spellcaster of the target religion. Drives proselytizing directly via the Faith block's `dispatch_missionaries` + `cast_charitable_spells` activities. Receives the full divine-ruler driver bonus per §5.4.
- **Non-divine ruler + driving caster.** Ruler is not a divine caster (Fighter, Paladin, Anti-Paladin, Mage, Thief, etc.). They declare the religion change via the Change Religion decree per §6.1 and EITHER hire missionaries via `dispatch_missionaries` (which only requires gp for hireling wages — no divine spellcaster needed) OR engage a **driving caster** — a divine-caster henchman OR a spiritual-advisor NPC of the target religion — who runs the Faith activities on the ruler's behalf. The spiritual advisor relationship per `rules/acore-campaign-general-and-magic-research.xml:578` gates this: must be the highest-level divine caster of the target religion with Friendly (or better) relations to the ruler.
- **Missionary-only.** Non-divine ruler with no driving caster registered. The arc still proceeds via `dispatch_missionaries` alone (a Fighter, Anti-Paladin, or Mage can pay hireling missionaries the same as a Cleric can). This is the slowest path but always available. The missionaries don't accumulate congregants under a specific caster's banner — they accumulate against an abstract "ruler-led proselytizing" bucket for the conversion's purposes (§5).

---

## 4. Data Model

### 4.1 Schema changes (migration 128)

Migration 128 (Phase 11D.3 — Alignment effects + Religion conversion implementation) lands the following:

**Augment `domains`:**

```sql
ALTER TABLE domains ADD COLUMN effective_religion TEXT NOT NULL DEFAULT '';
```

Semantics:
- `domains.religion` becomes the **declared religion** — what the ruler has decreed.
- `domains.effective_religion` is the **practiced religion** — what the population actually worships. This is the alignment-determining field per `acore_axioms` L466.
- For new domains, both fields are set to the same value at establishment.
- For domains created before migration 128, `effective_religion` is backfilled from the existing `religion` column.
- During an active conversion, `religion ≠ effective_religion` and the alignment penalty is active.

**Extend `congregants` to per-character-per-domain (Q-RC-5 resolution: full rebuild):**

The existing `congregants` table (`character_id PRIMARY KEY`) is rebuilt via the legacy_alter_table pattern (migrations 117 / 119 / 125 / 126):

```sql
PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;
BEGIN TRANSACTION;

ALTER TABLE congregants RENAME TO congregants_old;

CREATE TABLE congregants (
    id                          TEXT    PRIMARY KEY,
    character_id                TEXT    NOT NULL REFERENCES characters(id),
    domain_id                   TEXT    NOT NULL,  -- no FK; tracks even after domain teardown
    count                       INTEGER NOT NULL DEFAULT 0 CHECK(count >= 0),
    monthly_growth_pending_cp   INTEGER NOT NULL DEFAULT 0 CHECK(monthly_growth_pending_cp >= 0),
    last_resolved_calendar_day  INTEGER NOT NULL DEFAULT 0,
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX idx_congregants_caster_domain ON congregants(character_id, domain_id);
CREATE INDEX idx_congregants_domain ON congregants(domain_id);

-- Backfill: assign each existing row to the caster's primary domain.
-- For dev-test rows without a resolvable primary domain, domain_id='' is a sentinel
-- (matches the existing migration 119 pattern for unscoped data).
INSERT INTO congregants (id, character_id, domain_id, count, monthly_growth_pending_cp, last_resolved_calendar_day, created_at, updated_at)
SELECT
    -- Generate a fresh id (the old PK was character_id).
    lower(hex(randomblob(16))),
    character_id,
    COALESCE(
        (SELECT id FROM domains WHERE owner_character_id = congregants_old.character_id ORDER BY created_at LIMIT 1),
        ''
    ),
    count, monthly_growth_pending_cp, last_resolved_calendar_day, created_at, updated_at
FROM congregants_old;

DROP TABLE congregants_old;

COMMIT;
PRAGMA foreign_keys = ON;
```

Total congregant count for a caster (used for the 1gp/congregant maintenance check) is computed on demand via `SELECT SUM(count) WHERE character_id = ?`.

**New `domain_religion_conversion` table:**

```sql
CREATE TABLE domain_religion_conversion (
    id                          TEXT    PRIMARY KEY,
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    domain_id                   TEXT    NOT NULL REFERENCES domains(id),
    from_religion               TEXT    NOT NULL,
    to_religion                 TEXT    NOT NULL,
    from_alignment              TEXT    NOT NULL
        CHECK(from_alignment IN ('lawful', 'neutral', 'chaotic')),
    to_alignment                TEXT    NOT NULL
        CHECK(to_alignment IN ('lawful', 'neutral', 'chaotic')),
    -- progress_pct is a UI convenience derived from
    -- (target-religion congregants in domain) / (peasant_families × 0.60).
    -- The canonical completion check reads congregants directly, NOT this field.
    progress_pct                INTEGER NOT NULL DEFAULT 0
        CHECK(progress_pct BETWEEN 0 AND 100),
    driving_character_id        TEXT    REFERENCES characters(id),  -- nullable if missionary-only
    started_calendar_day        INTEGER NOT NULL,
    last_progressed_calendar_day INTEGER NOT NULL DEFAULT 0,
    status                      TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'completed', 'aborted', 'failed_morale')),
    total_invested_cp           INTEGER NOT NULL DEFAULT 0,  -- audit: cumulative proselytizing
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_drc_domain_active ON domain_religion_conversion(domain_id, status);
CREATE INDEX idx_drc_campaign_active ON domain_religion_conversion(campaign_id, status);
```

Only ONE active conversion per domain at a time (enforced by repository-level check at write).

### 4.2 Implicit data: spiritual advisor relationship

The driving-caster relationship per `rules/acore-campaign-general-and-magic-research.xml:578` ("highest-level divine spellcaster with Friendly relations to the ruler") is computed on-demand from existing data: character class, character level, henchman relations (loyalty), realm-relations table. No new column needed. The eligibility lookup is `RealmRepository.eligible_spiritual_advisor_for(ruler_character_id, religion) -> character_id` — added in 11D.3.

---

## 5. Conversion Pipeline

### 5.1 Canonical state: congregants against the 60% threshold

Per Q-RC-7 resolution, the canonical state of a conversion arc is **the count of target-religion congregants in the domain vs. peasant_families × 0.60**. When that ratio is reached, conversion completes atomically. There is no abstract `progress_pct` advancing toward 100% — there is only the literal congregant count growing toward the 60% threshold.

The `domain_religion_conversion` row carries a `progress_pct` column for UI display:

```
progress_pct = min(100, floor(100 × congregants_of_target_religion_in_domain
                              / (peasant_families × 0.60)))
```

But the canonical completion check is `congregants_in_domain ≥ peasant_families × 0.60`. The 60% threshold is the project's interpretation of "religious practice determines alignment" — a clear majority is needed to flip perceived alignment, not a knife-edge plurality. 60% acknowledges that agrarian religious practice tends toward whichever religion has the most active infrastructure (priests + temples + visible ritual), and a clear majority is required for the population to be PERCEIVED as following the new religion.

### 5.2 Top-level monthly resolver

Runs as part of `DomainHandlers._handle_monthly_tick` after revenue / expenses / morale / Faith-block activities resolve. Lands in 11D.3.

```
For each active domain_religion_conversion row (status='active'):
  1. Read peasant_families and current target-religion congregants in domain.
  2. RESOLVE MORALE GATE → morale_multiplier per §5.3.
  3. SUM ACTUAL PROSELYTIZING this month:
     - Each driving caster's charitable spell gp value (cast_charitable_spells output)
     - Missionary hireling wage gp (dispatch_missionaries output)
     - Religious-structure gp value (consecrated_altars of target religion;
       future: urban-settlement temples per §9.8)
  4. COMPUTE CONGREGANT GAIN per RAW formula × multipliers (§5.4).
  5. APPLY GAIN to per-domain congregants table (capped by
     peasant_families − existing-target-religion-congregants).
  6. UPDATE progress_pct UI value from the new congregant count.
  7. CHECK COMPLETION → if congregants_in_domain ≥ peasant_families × 0.60: §5.6.
  8. CHECK FAILURE MODES → §7 (morale collapse, ruler death stall).
  9. WRITE LOG ENTRY → DepartureLogRecorder on meaningful thresholds
     (every 10% of progress_pct + on completion / failure).
```

### 5.3 Morale gate (Q-RC-2 resolved — linear curve confirmed)

Conversion progress scales linearly with current domain morale, paralleling the Domain Worship table's morale-determines-divine-power scaling per `rules/acore-campaign-general-and-magic-research.xml:580-595`:

| Domain morale | morale_multiplier | Effect on conversion |
|---|---|---|
| −4 or worse (Rebellious) | 0.00× | Conversion STALLS — no new congregants accrue toward this conversion this month |
| −3 (Defiant) | 0.25× | Quarter-rate; conversion crawls |
| −2 (Turbulent) | 0.50× | Half-rate |
| −1 (Demoralized) | 0.75× | Three-quarter-rate |
| 0 (Apathetic) | 1.00× | Baseline |
| +1 (Loyal) | 1.25× | Mild bonus |
| +2 (Dedicated) | 1.50× | Notable bonus |
| +3 (Steadfast) | 1.75× | Strong bonus |
| +4 (Stalwart) | 2.00× | Conversion proceeds twice as fast |

Note: morale gates *new conversion-relevant congregant gain*, not the caster's overall congregation. A divine caster proselytizing in a Rebellious domain still gains personal congregants per RAW; they just don't count toward this conversion's threshold during stall months. (Implementation detail: the conversion arc tracks a delta-since-conversion-started congregant count, separate from the caster's lifetime congregation total.)

### 5.4 Congregant gain formula (Q-RC-1 resolved — v1 numbers confirmed)

The base congregant gain follows the RAW formula from `rules/acore-campaign-general-and-magic-research.xml:559-565`. Project-designed multipliers nudge it:

```
base_gain = floor(total_proselytizing_gp_this_month / 1000) × (1d10 + Cha_mod)

gain_modified = base_gain
                × morale_multiplier (§5.3)
                × driver_bonus
                × altar_bonus

actual_gain = min(gain_modified,
                  peasant_families − existing_target_religion_congregants_in_domain)
```

The cap at the end is the RAW "cannot gain more congregants than exist in the realm being proselytized" rule (`acore-campaign-general-and-magic-research.xml:565`).

**Where the proselytizing gp comes from** (per RAW):
- `cast_charitable_spells` activity — gp value of charitable spells cast (Spell Availability by Market table prices). Requires a divine caster.
- `dispatch_missionaries` activity — hireling wages paid for missionary work. Does NOT require a divine caster — any ruler can pay hirelings.
- Religious structures of the target religion erected in the realm:
  - v1: consecrated altars of matching religion (Phase 10A.2 infrastructure).
  - Future: temples in urban settlements once urban-growth stocking ships per §9.8.

**Cha_mod** is the Charisma bonus of the **driving caster** if one is registered, or the **ruler's** Cha bonus on the missionary-only path.

**v1 multiplier values:**

- `driver_bonus`:
  - Divine-caster ruler of the target religion present in the domain: **1.5×**.
  - Spiritual-advisor NPC of the target religion (Friendly + highest-level applicable): **1.25×**.
  - Henchman divine caster of the target religion in the domain (not advisor): **1.10×**.
  - Missionary-only (no driving caster): **1.0×**. No explicit penalty — the RAW economics (slower gp investment yields slower progress) drive the path.
- `altar_bonus`:
  - `1.0 + (0.1 × count_of_consecrated_altars_of_target_religion_in_domain)`, capped at **1.5×** (max 5 altars contribute).

**Worked example A — chaotic Cleric (NOT Anti-Paladin) converts a 500-family lawful kingdom:**
- Cleric Cha 13 (+1 mod). 500 fam × 0.60 = 300 target congregants needed.
- Monthly proselytizing: 1,000gp missionaries + 500gp charitable spells + 500gp consecrated-altar value = 2,000gp.
- `base_gain = 2 × (1d10 + 1) ≈ 2 × 6.5 = 13 congregants/month average`.
- Domain morale 0 (Apathetic) → 1.0×.
- Cleric is divine ruler in domain → 1.5×.
- 1 consecrated chaotic altar → 1.1×.
- `gain_modified ≈ 13 × 1.0 × 1.5 × 1.1 ≈ 21.5 congregants/month`.
- Time to 300 congregants: **~14 months**. Plausible — a major political project completed in just over a year.

**Worked example B — lawful Fighter (not divine) converts a 500-family chaotic domain, missionary-only:**
- Fighter Cha 10 (+0 mod). 500 fam × 0.60 = 300 target congregants needed.
- Monthly proselytizing: 1,500gp missionaries (Fighter cannot cast charitable spells; cannot consecrate altars personally — the altar activity requires divine-caster level 5+ per `ax_campaign_play.xml:411-421`).
- `base_gain = 1 × (1d10 + 0) ≈ 5.5 congregants/month average` (1,500gp rounds DOWN to 1 full 1000gp unit per the RAW "for each full 1,000gp" wording; the residual 500gp doesn't count).
- Morale −2 (Turbulent — population alienated by new lawful religion) → 0.5×.
- No driving caster → 1.0×.
- 0 altars → 1.0×.
- `gain_modified ≈ 5.5 × 0.5 × 1.0 × 1.0 ≈ 2.75 congregants/month`.
- Time to 300 congregants: **~109 months ≈ 9 years**. **Brutal.** A non-divine ruler is essentially incapable of converting a hostile chaotic domain via missionaries alone at modest investment.

**Worked example C — same lawful Fighter, after recruiting a Cleric spiritual advisor and bumping investment to 3,000gp/month:**
- Cleric advisor Cha 14 (+1 mod). 300 congregants needed.
- 3,000gp/month: `base_gain = 3 × (1d10 + 1) ≈ 19.5 congregants/month`.
- Morale −2 → 0.5×.
- Spiritual advisor driver → 1.25×.
- altar_bonus 1.0×.
- `gain_modified ≈ 19.5 × 0.5 × 1.25 × 1.0 ≈ 12.2 congregants/month`.
- Time to 300: **~25 months ≈ 2 years**. **Achievable** with investment + advisor.

The Fighter's path to conversion is "either pay massively + accept years of −3 stacked morale, or recruit a divine-caster advisor + still accept years." This matches the RAW intent that religion conversion is a major political-religious undertaking.

### 5.5 In-progress morale penalty

While `domain_religion_conversion.status='active'`, the domain takes an additional **−1 base morale** on top of the existing −1 / −2 ruler-vs-domain alignment penalty per `rules/acore_axioms_strongholds_and_domains.xml:245` ("Changing religion is possible but causes severe morale penalties"). The active conversion is destabilizing in itself; the population resents the disruption of their religious practice.

Stacking implications in the worked examples:

- Worked example A: ruler is chaotic + domain is still lawful (alignment hasn't shifted yet) → alignment penalty −2 + conversion penalty −1 = **−3 base morale during the arc**. The cleric must invest in morale recovery (consecrate_ruler, altars, etc.) to keep morale above −4 (the conversion-stalling threshold).
- Worked example B: same −3 stack, plus the missionary-only path's natural slowness compounds. Without morale recovery the conversion likely never reaches threshold.

The conversion penalty clears the moment `status` transitions out of `active` (completion, abort, or failure).

### 5.6 Completion (Q-RC-7 resolved — atomic shift at 60% threshold)

Completion triggers when **congregants_of_target_religion_in_domain ≥ peasant_families × 0.60**. The check happens at the end of the monthly tick after congregant gain has been applied.

1. `domain_religion_conversion.status` → `'completed'`. `last_progressed_calendar_day` updated.
2. `domains.effective_religion` → conversion row's `to_religion`.
3. `domains.alignment` → conversion row's `to_alignment` (the new alignment derived from new religion).
4. `domains.religion` is already `to_religion` (set at declaration); no change needed.
5. **Recompute realm alignment** — `RealmRepository.recompute_realm_alignment(realm_id)` per the chaotic-realm RAW rule (`ax_domains_of_chaos.xml:96-103` — a realm with at least one chaotic domain is a chaotic realm).
6. Conversion penalty clears (no more −1 from §5.5).
7. Alignment penalty re-evaluates — if the ruler's alignment now matches the new domain alignment, the penalty drops to 0. If not (e.g., neutral ruler completing a conversion of a domain from lawful to chaotic — they're now ruling a chaotic domain as a neutral character), the new −1 mismatch persists.
8. Departure log entry: `event_type='religion_converted'`, payload `{from_religion, to_religion, from_alignment, to_alignment, calendar_day_completed, total_invested_cp, driving_character_id, congregants_at_completion, peasant_families_at_completion, months_to_completion}`.
9. EventBus signal: `religion_conversion_completed(domain_id, from_religion, to_religion)` (new signal — added in 11D.3).

The 40% of the population NOT in the new religion's congregation remains in the old religion. They are still mechanically subject to the new alignment (since `effective_religion` flipped), but they may serve as a seed for future counter-conversions or as a source of unrest (Phase 12+ faction work may model this).

### 5.7 Multi-caster proselytizing

If multiple divine casters of the target religion proselytize the same domain (e.g., a Cleric ruler + a Bladedancer henchman + a spiritual-advisor NPC), their congregant gains stack toward the conversion threshold. Each caster's congregants accumulate in their own row in the per-domain `congregants` table (per §4.1); the §5.6 completion check sums across all target-religion casters in the domain.

Conversely, casters of OTHER religions in the same domain accumulate their own congregants but DO NOT contribute to the conversion arc. They may serve as a counter-conversion seed if the ruler later changes target religion (their congregants suddenly count toward a new arc).

---

## 6. Activity + Decree Integration

The conversion declaration (the act of saying "I am converting this domain to religion X") is a single Decree. The ongoing proselytizing inputs reuse existing Phase 10A.2 Faith activities. No new activities are introduced.

### 6.1 New decree: `change_religion`

Lives in [`gdd-domain-tab.md`](gdd-domain-tab.md) §11 (Decrees & Remote Orders sub-tab) as a new decree card. v1 specification:

- **Activity classification:** singular minor, location-gated to a stronghold the ruler personally controls (the ruler must declare from a seat of authority — being adventuring on the other side of the map doesn't suffice).
- **Inputs:** target religion string (free-form in v1; eventually constrained to the setting generator's religion catalog).
- **Validation:**
  - Reject if the domain already has an active `domain_religion_conversion` row.
  - Reject if `to_alignment` would violate a style/alignment constraint per [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §7 (e.g., declaring a lawful religion for a beastman clanhold — beastman clanholds are force-locked chaotic).
  - Warn (do not reject) if the alignment shift would create a stacked morale penalty of −3 or worse (e.g., chaotic ruler converting a lawful kingdom — the alignment penalty alone is −2, plus the conversion penalty −1 = −3 from day one). The Decrees sub-tab modal shows the warning copy.
- **Effects:**
  - `domains.religion` updates immediately to the new value.
  - A `domain_religion_conversion` row is inserted with `progress_pct=0`, `from_religion = effective_religion`, `to_religion = new value`, derived alignments, `driving_character_id` set if the ruler is themselves a divine caster of the new religion OR if a spiritual advisor of the new religion is already registered for the ruler.
  - Departure log entry: `event_type='religion_converted'` with `status='initiated'` in the payload.
  - EventBus signal: `religion_conversion_started(domain_id, from_religion, to_religion)`.

### 6.2 Faith block surface (Class-Specific sub-tab §12.2)

The Faith block (already shipped in Phase 10A.2 for divine-caster classes) gets a new card in 11D.3:

- **Religion Conversion card.** Visible only when an active conversion exists for the active entity's domain OR the active entity is the registered `driving_character_id` for some other domain's conversion. Renders:
  - Conversion progress bar (0-100% based on congregants / (peasant_families × 0.60))
  - From → to religion + alignment chips
  - Domain morale state + current morale_multiplier (read-only display so the player understands why progress is slow)
  - Driving caster (this entity or another) + role chip (ruler / spiritual_advisor / henchman / missionary-only)
  - This month's congregant gain
  - Cumulative invested cp
  - "Cancel Conversion" button (with destructive-action gate per §7.2)

The existing `dispatch_missionaries` and `cast_charitable_spells` cards stay unchanged — they're the proselytizing inputs. The Faith block visually highlights when these activities feed into an active conversion (a small "→ Conversion" pip on the activity card).

### 6.3 Non-divine ruler workflow

A non-divine ruler (Fighter, Paladin, Anti-Paladin, Thief, Mage) does NOT see the Faith block on their Class-Specific sub-tab. They drive conversion via:

1. **Decree the religion change** from the Decrees sub-tab.
2. **Recruit a spiritual advisor** — the realm sub-tab gains a "Spiritual Advisor" row in 11D.3 surfacing the highest-level eligible divine caster among their henchmen + offering NPC-recruitment paths. The advisor becomes the `driving_character_id` for the conversion.
3. **OR proceed missionary-only** — the ruler can still use `dispatch_missionaries` (which doesn't require a divine caster, just hireling wages) via the location-gated activity. This is the slowest path but always available.

### 6.4 Proselytizing target picker (Q-RC-8 resolved — UI picker confirmed)

When a divine-caster ruler has multiple domains OR is acting as spiritual advisor to multiple rulers, the `dispatch_missionaries` + `cast_charitable_spells` activity cards in the Faith block surface a **target-domain dropdown** in 11D.3. The dropdown lists every domain the caster is eligible to proselytize in (own domains + advised domains); if exactly one option exists the dropdown auto-selects and is read-only.

Resulting congregants land in the picked domain's per-domain `congregants` row (per §4.1). The conversion-progress monthly resolver (§5.2) only counts congregants in the conversion's target domain — proselytizing investment toward a different domain doesn't contribute to a conversion arc elsewhere, even if the caster's religion matches.

This makes domain-specific conversion targeting explicit: a Cleric ruler with two domains, one undergoing conversion, must direct their proselytizing investment to the domain under conversion to make progress.

---

## 7. Failure Modes

Four ways a conversion ends without success. Heresy / excommunication is intentionally OUT of v1 per Q-RC-4 resolution.

### 7.1 Stalled (progress doesn't reach the 60% threshold)

Not a "failure" per se — the conversion row stays `active` indefinitely if morale gating + zero proselytizing zero out the congregant gain. The ruler can pump in investment to resume.

### 7.2 Cancelled (player abort)

The ruler chooses to abort. `status='aborted'`. Effects (Q-RC-3 resolved — forfeit confirmed):

- `domains.religion` reverts to `domains.effective_religion` (un-declares the religion change).
- The −1 conversion penalty clears.
- The −1 / −2 alignment penalty re-evaluates against the original religion.
- All accumulated `total_invested_cp` is forfeit. Congregants gained by the driving caster are NOT lost (they remain in the per-domain congregants table); the caster keeps their personal congregation. The domain just goes back to the prior religion as if no decree was issued.
- Departure log entry: `event_type='religion_converted'` with `status='aborted'`, payload includes `congregants_at_abort`, `target_threshold`, and `total_invested_cp_forfeit`.
- v1 has a 12-month cooldown on re-declaring conversion for the same domain after an abort (project-designed; prevents oscillation; tunable).

### 7.3 Failed by morale collapse

If the domain's morale reaches Rebellious (−4) AND stays there for 3+ consecutive months while a conversion is active, the conversion fails. `status='failed_morale'`. Effects:

- Same revert behavior as cancellation (domain returns to effective_religion).
- `total_invested_cp` forfeit.
- Additional penalty: **−2 to next domain morale roll** (the conversion attempt has now been publicly humiliated; population gloats).
- Departure log entry: `event_type='religion_converted'` with `status='failed_morale'`.

### 7.4 Ruler / driving-caster death

Per [`gdd-domain-tab.md`](gdd-domain-tab.md) §16.5 (succession), when a ruler dies the domain enters `succession_pending` for 1 game month. During this period:

- If the conversion has a registered `driving_character_id` ≠ the deceased ruler, the conversion continues (the driving caster's death is the gating event, not the ruler's).
- If the deceased ruler IS the driving caster, the conversion **stalls** (congregants accrue at 0× even with high morale + investment) until a new driving caster is registered.
- The new heir (per the succession resolution) inherits the conversion. If the heir's alignment is misaligned with the conversion target, an automatic abort is offered (modal warning) — the player may keep the conversion active if they want (e.g., heir is willing to ride out the alignment penalty), but the default is "abort the now-pointless conversion."

---

## 8. UI Surface

Phase 11D.3 implements the following UI affordances. Most are extensions of existing surfaces from Phase 10A.2 / Phase 2.

### 8.1 Decrees & Remote Orders sub-tab

- New decree card "Change Religion" — drives the §6.1 flow.
- Active conversion banner (visible while a conversion is in-progress for the active entity's domain): one-line summary with progress %, morale state, and "View details" link to the Faith block (for divine rulers) or the Realm sub-tab Spiritual Advisor section (for non-divine).

### 8.2 Faith block (Class-Specific sub-tab §12.2)

- New "Religion Conversion" card per §6.2. Card is collapsible.
- Activity cards for `dispatch_missionaries` + `cast_charitable_spells` get a small "→ Conversion" pip + tooltip when an active conversion exists.
- New target-domain dropdown on `dispatch_missionaries` + `cast_charitable_spells` cards per §6.4 (Q-RC-8 resolution).

### 8.3 Status header

The Domain Status header (a row across all sub-tabs per `gdd-domain-tab.md` §5) gains a banner row in 11D.3 (parallel to the Phase 11C succession banner):

> ⚠ **Religion conversion in progress** · From X → To Y · 42% (126 / 300 congregants) · domain morale Apathetic (1.00×) · estimated 12 months to completion

The banner is shown only while the active entity's domain has an active conversion. Hidden otherwise. Clicking the banner navigates to the Faith block Religion Conversion card (divine ruler) or the Decrees sub-tab active conversion view (non-divine ruler).

### 8.4 Departure log

The existing `religion_converted` event_type from Phase 11A's migration 121 CHECK constraint handles all conversion log entries. The `full_details_json` payload disambiguates `status` (initiated / progressing / completed / aborted / failed_morale).

---

## 9. Cross-System Integration

### 9.1 Domain Morale Resolver (11D.3)

`DomainMoraleResolver.resolve_base_morale` consumes the conversion-active state:

- Adds the −1 conversion penalty when an active `domain_religion_conversion` row exists.
- The alignment penalty (per `acore_axioms` L467-470) reads `domains.alignment` (which is derived from `effective_religion`, not from `religion`). So during a conversion, the alignment penalty reflects the ORIGINAL alignment, not the target alignment. This is the intended behavior — the −2 misalignment persists for the whole arc.

### 9.2 LifecycleHandler conquest path

Per [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §8.1, the conquest path does NOT initiate religion conversion automatically. The new ruler must explicitly issue the Change Religion decree per §6.1 — conquest itself only reassigns ownership. The −2 alignment penalty applies from conquest day forward; the ruler chooses whether to bear it indefinitely (Q-DSA-1 resolution: no special UI) or to launch a conversion arc to clear it.

### 9.3 Succession (11C handler)

Per §7.4, the `RulerDeathHandler` checks for active conversions when resolving succession. The conversion may continue under the heir or auto-abort depending on heir alignment.

### 9.4 Realm alignment recompute

When a conversion completes, `RealmRepository.recompute_realm_alignment(realm_id)` fires per §5.6 step 5. This is a new helper added in 11D.3:

```gdscript
static func recompute_realm_alignment(realm_id: String) -> bool
    # Reads all constituent domains' alignments.
    # If any domain is chaotic → realm.alignment = 'chaotic' (chaotic realm per
    #     ax_domains_of_chaos.xml:96-103).
    # Else if any domain is lawful AND no domain is chaotic → realm.alignment = 'lawful'.
    # Else → realm.alignment = 'neutral'.
    # Updates realms.alignment if changed. Emits realm_alignment_recomputed signal.
```

### 9.5 Faith block proselytizing inputs

The existing Phase 10A.2 `dispatch_missionaries` + `cast_charitable_spells` handlers continue to work unchanged. The monthly Faith resolver (`FaithMonthlyResolver` per Phase 10A.2) credits congregants per the RAW formula. In 11D.3, an additional step in the resolver:

```
For each newly-acquired congregant:
  - Identify the domain those congregants live in (per §6.4: caster's selected
    target domain via the dropdown; falls back to caster's primary domain
    if no explicit selection).
  - INSERT or UPDATE congregants(character_id, domain_id, count) row.
  - If domain has an active conversion AND caster's religion == to_religion,
    these congregants count toward the conversion's monthly contribution.
```

The §5.4 congregant-gain formula reads from this per-domain congregant breakdown, not from a per-character total.

### 9.6 Spiritual advisor relationship lookup

New `RealmRepository` helper:

```gdscript
static func eligible_spiritual_advisor_for(ruler_character_id: String, religion: String) -> String
    # Returns the character_id of the highest-level divine caster of `religion`
    # with Friendly (or better) relations to the ruler. Per
    # acore-campaign-general-and-magic-research.xml:578.
    # Returns empty string if no eligible advisor exists.
```

Consumed by the Change Religion decree to auto-populate `driving_character_id` when possible.

### 9.7 Beastman-clanhold lock

Per [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §3.2 and §3.3, beastman clanholds are force-locked to chaotic alignment. The Change Religion decree validation (§6.1) must reject any `to_religion` whose `to_alignment ≠ 'chaotic'` for a beastman-populated clanhold. v1 inference per [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §9.7: a clanhold-style domain whose establishment_method is `clanhold_annex` or `recruit_chieftain` is beastman-populated; other clanholds (kin clanholds from `METHOD_CLEAR`) may convert freely.

### 9.8 Urban Growth Stocking — deferred project-wide dependency (Q-RC-9)

**The gap.** ACKS RAW's monthly proselytizing formula counts "religious structures erected in the realm" as a third gp-value source (`rules/acore-campaign-general-and-magic-research.xml:565`). The full implementation of this requires:

- Urban settlements gaining temple POIs as they grow in market class.
- Rulers being able to "stock" those temples with clerics of specific religions (a player action, NOT automatic) so the clerics can serve as missionary multipliers.
- The temple POIs producing a gp-value contribution to proselytizing in the domain that contains the urban settlement.

This is a **project-wide architectural gap** flagged by Jedidiah during the v1.0 draft review. Arbiter currently has no urban-growth-stocking system — no mechanic that decides "when this settlement grows from class V to class IV, two temples appear and one of them needs a cleric." The mechanic should be built as part of the broader domain play system; it interacts with settlement-shop generation, NPC population, faction allegiance, and other systems beyond religion conversion.

**v1 stub.** Until urban-growth stocking ships, the religious-structure contribution to proselytizing comes ONLY from `consecrated_altars` (already in Phase 10A.2). The Faith block's `consecrate_altar` activity is the player's only lever for boosting proselytizing via religious structures. The non-divine ruler is at a particular disadvantage here — `consecrate_altar` requires a divine-caster level 5+, so a Fighter / Anti-Paladin without a divine henchman has no path to religious-structure contribution beyond hiring missionaries.

**Future integration.** When the urban-growth-stocking GDD ships:
- Temples in urban settlements gain a `religion` attribute + `stocked_cleric_character_id` field.
- The proselytizing-sum step in §5.2 picks up temple gp value for each temple whose religion matches the conversion's to_religion.
- A "Stock Temple" decree or activity lets the ruler assign a divine-caster henchman / NPC to a specific temple, after which that cleric's class-driven proselytizing is amplified by the temple's infrastructure.
- The `gdd-religion-conversion.md` and Phase 11D.3 implementation will need a follow-up patch to consume the new temple infrastructure — this is captured in the project handoff for the future urban-growth-stocking work.

This GDD does NOT block on urban-growth stocking; v1 ships with the consecrated_altars-only path. But Phase 11D.3's `ReligionConversionResolver` must be written to accept a pluggable "religious_structures_gp_value_for_domain(domain_id, religion)" helper so the temple integration is a drop-in extension later.

---

## 10. Implementation Roadmap (Phase 11D.3)

Per [`docs/phase-11-plan.md`](../docs/phase-11-plan.md) §11D.3, the religion conversion mechanic ships alongside the alignment-vs-religion morale penalty + the beastman-rules-kin stack. Specifically:

- **Migration 128** lands: (a) full `congregants` table rebuild per §4.1 (per-character-per-domain); (b) new `domain_religion_conversion` table per §4.1; (c) `domains.effective_religion` column add.
- **`ReligionConversionResolver`** (new static class, `engine/subsystems/domains/religion_conversion_resolver.gd`): owns the monthly pipeline per §5. Public API:
  - `start_conversion(domain_id, to_religion, driving_character_id, calendar_day) -> String` (returns the new conversion id; called by the Change Religion decree handler).
  - `tick_conversion(domain_data, calendar_day) -> Dictionary` (called by `DomainHandlers._handle_monthly_tick` per active conversion; returns `{congregant_gain, status_change, log_entry_payload}`).
  - `abort_conversion(conversion_id, calendar_day, reason) -> bool` (called by Cancel Conversion button + failure-mode triggers).
  - `eligible_conversion_targets(domain_id) -> Array` (returns valid `to_religion` strings per the beastman-clanhold-lock + other constraints).
  - `religious_structures_gp_value_for_domain(domain_id, religion) -> int` (per §9.8 — pluggable helper; v1 sums consecrated_altars only).
- **`Change Religion` decree handler** (`engine/subsystems/activities/handlers/change_religion_decree.gd`): wraps the decree's location-gating + validation + `ReligionConversionResolver.start_conversion` call.
- **`DomainMoraleResolver`** extension: read active conversion state; add −1 conversion penalty; the existing alignment-vs-religion penalty already reads from `domains.alignment` so no change is needed there beyond ensuring `alignment` is updated only at conversion completion (not at declaration).
- **`FaithMonthlyResolver`** extension: per-domain congregant placement (§9.5) + the target-domain dropdown selection from §6.4.
- **EventBus signals** (new): `religion_conversion_started(domain_id, from_religion, to_religion)`, `religion_conversion_progressed(domain_id, conversion_id, new_congregant_count)`, `religion_conversion_completed(domain_id, from_religion, to_religion)`, `religion_conversion_aborted(domain_id, reason)`.
- **UI surfaces** per §8 (Decrees decree card; Faith block conversion card; status header banner; target-domain dropdown on Faith activities).
- **Tests**: a new `tests/test_religion_conversion.gd` suite covers: declaration writes the row + decree validation, monthly congregant gain at various morale levels, driver-bonus tiers, altar bonus, completion-at-60% flips alignment + recomputes realm alignment, abort forfeits investment, morale collapse triggers failed_morale, succession-with-mismatched-heir auto-abort prompt, beastman clanhold rejects lawful-religion decree.

---

## 11. Resolved Decisions

All Q-RC-* items raised in v1.0 draft were resolved by Jedidiah on 2026-05-20. Resolutions are folded into the relevant sections; this list is the audit trail.

1. **Q-RC-1 (RESOLVED 2026-05-20): Baseline progress rate + formula coefficients.** The v1.0 proposed numbers are confirmed as the starting point: `driver_bonus` tiers 1.5× / 1.25× / 1.10× / 1.0×; `altar_bonus = 1.0 + 0.1 × altars` cap 1.5×; RAW 1d10 + Cha per 1000gp base. Numbers will be tuned post-implementation if play testing surfaces issues. Worked examples in §5.4 show ~14-month divine-driven and ~109-month missionary-only conversions of a 500-family domain. (Folded into §5.4.)

2. **Q-RC-2 (RESOLVED 2026-05-20): Morale-multiplier linear curve confirmed.** 0.00× at Rebellious through 2.00× at Stalwart, linearly scaled. (Folded into §5.3 — note removed from §5.3 about "alternatives considered.")

3. **Q-RC-3 (RESOLVED 2026-05-20): Cancellation forfeit policy confirmed.** All `total_invested_cp` is forfeit on abort. Caster's personal congregation is preserved (they keep what they gained). 12-month cooldown on re-declaring on the same domain post-abort. (§7.2.)

4. **Q-RC-4 (RESOLVED 2026-05-20): Heresy / excommunication subsystem REMOVED from v1.** Needlessly complex prior to a working game. The §7.4 heresy stub is deleted entirely. Heresy and excommunication mechanics deferred to Phase 12+ faction / cult conflict work. The `failed_heresy` status value is dropped from the `domain_religion_conversion` CHECK constraint. (§7 reduced from five subsections to four; §2 ACKS Constraints note on tithes-heresy link remains as a documentation anchor but is explicitly deferred.)

5. **Q-RC-5 (RESOLVED 2026-05-20): Full rebuild of the `congregants` table.** Per the conventions §57+ rename-cleanly-via-parse-failure pattern. Migration 128 rebuilds the table using the legacy_alter_table pattern; the SQL is in §4.1. (Folded into §4.1.)

6. **Q-RC-6 (RESOLVED 2026-05-20): No cooldown on conversion of newly-established domains.** Conquest-driven conversion arcs are first-class per [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §8.1; we don't artificially block them. (No section changes — this was the v1.0 draft default.)

7. **Q-RC-7 (RESOLVED 2026-05-20): Atomic alignment shift at 60% of populace converted.** The canonical conversion state is the congregant count against `peasant_families × 0.60`, not an abstract `progress_pct`. Completion fires atomically when the threshold is crossed. The `progress_pct` column remains as a UI convenience derived from the ratio. (Substantial §5 rewrite — §5.1 introduces the canonical state framing; §5.6 specifies the threshold check; §5.4 worked examples recomputed against the new model.)

8. **Q-RC-8 (RESOLVED 2026-05-20): UI picker for proselytizing target.** When a divine-caster ruler has multiple eligible domains, the `dispatch_missionaries` and `cast_charitable_spells` activity cards in the Faith block surface a target-domain dropdown. Single-option case auto-selects and is read-only. (§6.4 added.)

9. **Q-RC-9 (RESOLVED 2026-05-20): Urban Growth Stocking is a deferred project-wide dependency.** No urban-growth stocking system exists in Arbiter today. v1 religion conversion ships with consecrated_altars-only as the religious-structure source. The §10 implementation roadmap requires `ReligionConversionResolver.religious_structures_gp_value_for_domain(domain_id, religion)` to be pluggable so the future urban-growth-stocking GDD's temple infrastructure drops in cleanly. The urban-growth-stocking GDD itself is a separate project-wide work item (NOT a Phase 11D-prereq), flagged in the build_log for future scoping. (§9.8 added.)

---
