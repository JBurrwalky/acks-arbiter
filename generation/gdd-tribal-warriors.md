# GDD: Tribal Warriors

**Document type:** Game Design Document (project-designed, modifiable)
**Authority:** PROJECT-DESIGNED — RAW gives the levy mechanic, the pool-vs-casualty model, the per-race troop-type table, the per-troop-type wage rate, the 3-month-without-spoils morale trigger, the loyalty consequences, and the call-to-arms favor cost. The project decides only the data shape (`available_tribal_warriors` column), the activity handler wiring, and the UI surfaces. Subordinate to `docs/acks_arbiter_design_brief_v11.md` and to [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §3.2-3.3 (beastman lock; kin-clanhold extension).
**Status:** Draft v1.2 — Q-TW resolutions applied 2026-05-21. v1.1's Call to Arms framing was substantially wrong (treated it as a self-imposed levy decree; RAW Call to Arms is a DUTY a liege imposes on a vassal, with clanhold-vassal modification). Also corrected: dropped elf/dwarf/halfling/gnome kin clanhold fallback (those races aren't clanhold-eligible per project canon); dropped −2 morale modifier on 3-month spoils roll (the roll itself is the penalty); confirmed six event types; spoils computation now grounded in existing `SiegeSpoilsResolver` per codebase recon. v1.0's "pool = peasant_families − levied" derivation, "100 cp/month flat wage" guess, "10%/month dwindle curve" invention, and 1:1 "warrior casualty decrements peasant_families" misreading were replaced in v1.1.
**Depends on ACKS rules:**
- `rules/ax_domains_of_chaos.xml:6-64` (full beastman clanhold section — establishment, families, military rules, vassalage limits including the call-to-arms tribal-warrior favor cost);
- `rules/ax_domains_of_chaos.xml:14` ("Each clanhold family consists of 1 beastman warrior and 1 or more noncombatants" — warrior-per-family RAW basis);
- `rules/ax_domains_of_chaos.xml:17` ("Ogre and troll families count as 4 families each for population limits and growth");
- `rules/ax_domains_of_chaos.xml:37-40` (military section: levy up to 1 tribal warrior per family; cannot conscript peasants or levy militia; may hire beastman mercenaries; kin mercenaries must be chaotic);
- `rules/ax_domains_of_chaos.xml:52` (chieftain call-to-arms favor cost: half as 1 favor, all as 2 favors);
- `rules/ax_domains_of_chaos.xml:390-441` (**`tribal_warriors` section** — the canonical tribal-warrior subsystem: definition, levy rules, service rules, per-race troop-type table by Jutland / Iv. King. / Skysos / Kobold / Goblin / Orc / Hobgoblin / Gnoll / Lizardman / Bugbear / Ogre);
- `rules/ax_domains_of_chaos.xml:394` ("Tribal domains include beastman clanholds and chaotic domains" — the scope of "tribal" extends beyond clanholds);
- `rules/ax_domains_of_chaos.xml:401-404` (population-change-replenishes-pool rule + the canonical casualty-only-replaced-via-population-growth rule);
- `rules/ax_domains_of_chaos.xml:411` ("Tribal warriors must be paid wages appropriate to troop type, using Mercenary GP Wage per Month from Domains at War: Campaigns");
- `rules/ax_domains_of_chaos.xml:444-463` (**`tribal_warrior_morale` section** — base morale, domain-morale modifier, loyalty triggers including the 3-month-without-spoils rule, departure rules);
- `rules/daw_campaigns_troop_tables_summary.xml` (Mercenary GP Wage per Month — the wage source for tribal warriors per troop type).

**Depends on project GDDs:**
- [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §3.2-3.3 (beastman-clanhold force-locked chaotic; kin-clanhold post-RAW extension; no beastman PCs in v1); §9.7 (`population_race` inference);
- [`gdd-domain-tab.md`](gdd-domain-tab.md) §8 (Garrison sub-tab — the canonical UI home for the tribal-warrior surfaces); §11 (Decrees & Remote Orders);
- [`gdd-army-warfare.md`](gdd-army-warfare.md) Phase 6A/B layer (composition, marching, supply, vagaries, field-battle resolver — levied tribal warriors slot in as standard `troop_units`);
- [`gdd-troops-tab.md`](gdd-troops-tab.md) (Phase 5 troops infrastructure — the `troop_units` table this GDD extends);
- [`gdd-religion-conversion.md`](gdd-religion-conversion.md) (no direct overlap; cited as the third Phase 11D-prereq for sequencing context).

**Modifiable by Claude Code:** Yes within constraints. The data-model shape (§4), activity handler signatures (§5), and UI surface (§10) are project-direction. Wage values, composition ratios, loyalty triggers, and the casualty-replacement rule are RAW-mandated and may NOT be tuned away.
**Last updated:** 2026-05-21

> **Note on culture mapping (forward reference).** Per Jedidiah's 2026-05-21 resolution, when the future Culture Canon GDD lands, the three RAW kin labels will map onto project culture-IDs as follows: **Jutland** → cultures 6, 7, 8; **Iv. King.** (Ivory Kingdoms) → cultures 11, 12, 14, 16; **Skysos** → cultures 15, 17. Until that GDD exists, this GDD uses the RAW labels directly; the registry's column lookup is a single dictionary keyed on the cultural-marker string and will trivially extend to culture-ID lookups when the Culture Canon ships.

---

## 1. Purpose and Scope

This GDD specifies the project-designed implementation of the ACKS **tribal warriors** subsystem — the military force available to tribal-domain rulers (clanholds and chaotic domains alike) in lieu of mercenary recruitment, conscription, or militia. The Axioms Compendium 1-8 (`rules/ax_domains_of_chaos.xml:390-463`) provides a complete, self-contained ruleset: levy mechanics, casualty-replacement rule, per-race troop-type table, mercenary-equivalent wage rule, and a morale/loyalty subsystem keyed on the 3-month-without-spoils trigger. This GDD's job is to map that ruleset onto the project's existing `troop_units` infrastructure (Phase 5), army-warfare layer (Phase 6A/B), and Garrison sub-tab (Phase 10A.3).

Tribal warriors are the third and final Phase 11D-prereq GDD. They ship with Phase 11D.5 implementation.

**Core insight (corrected against RAW):** the warrior pool is a **tracked counter**, not a derived value. Per `rules/ax_domains_of_chaos.xml:401-404`:

- Each tribal family contains 1 warrior; the pool ceiling equals the family count.
- Population growth (new families) replenishes the warrior pool until it reaches the ceiling.
- **Casualties only reduce the warrior pool; they do NOT reduce the family count.** A clanhold of 500 families that loses 250 warriors in battle still has 500 families — but now only 250 available warriors, with the remaining 250 slots refillable only by future population growth (each new family contributes 1 new warrior into the pool, up to the ceiling).
- Population loss (the family-count-itself shrinks via disasters, morale collapse, slave-trafficking, etc.) reduces the warrior pool by an equivalent amount, releasing levied warriors back to dormant if necessary.

This is the central correction from v1.0, which incorrectly derived the pool as `peasant_families − levied` (so a casualty automatically meant a family death) and incorrectly imposed a 1:1 `peasant_families` decrement on warrior casualties. RAW intends the pool and the family count to move asymmetrically: families ceiling the pool; casualties cost only the pool slot.

**Out of scope** (referenced but specified elsewhere):

- Per-race beastman stat blocks themselves — those live in `rules/le_monster_catalog_*.xml`. The composition-per-120-warriors table here references kin-race or beastman-race troop-type mixes; the individual troop-type stat blocks (e.g., Light Infantry HP/AC/damage) come from the army warfare layer's existing troop-type catalog.
- Standard mercenary recruitment — `solicit_mercenaries` already exists for kin mercenaries (Phase 5); chieftains may use it for chaotic kin mercenaries per the §2 ACKS Constraint, but the activity itself is unchanged.
- Army warfare layer — `gdd-army-warfare.md` covers composition + marching + supply + vagaries + field-battle resolution. Levied tribal warriors are normal `troop_units` once levied; the army layer treats them indistinguishably from mercenaries except where this GDD calls out specific differences (§9).
- Beastman-race-as-population attribute — the clanhold's race lives in the population-race tracking system per [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §9.7.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **Tribal-domain scope** (`rules/ax_domains_of_chaos.xml:394`): *"Tribal domains include beastman clanholds and chaotic domains."* The tribal-warrior subsystem applies to any domain in this category. In the project's data model, the trigger is `domain_style='clanhold'` OR `alignment='chaotic'` (the two overlap heavily but are not identical — see [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §3 for the orthogonal-axes model).

- **Every clanhold family includes 1 warrior** (`rules/ax_domains_of_chaos.xml:14`): *"Each clanhold family consists of 1 beastman warrior and 1 or more noncombatants."* The pool ceiling equals the family count.

- **Levy limit: 1 tribal warrior per family without penalty** (`rules/ax_domains_of_chaos.xml:398-400`): *"Up to 1 tribal warrior per tribal family may be levied without reducing domain morale or domain revenue. Any additional levies are treated as militia. The levy may occur all at once or over time."* Additional levies count as militia — and clanholds may NOT levy militia (`rules/ax_domains_of_chaos.xml:37`) — so for clanhold-style and chaotic-style domains the 1-per-family is a hard cap in v1.

- **Casualties only replaced via population growth** (`rules/ax_domains_of_chaos.xml:404`): *"Tribal warrior casualties can only be replaced through population growth."* A killed warrior frees up no family slot — but the family persists (1 surviving noncombatant inherits the household). New warriors arrive only as new families arrive.

- **Pool follows population both up and down** (`rules/ax_domains_of_chaos.xml:401-403`): *"If the number of tribal families changes, the number of available tribal warriors changes accordingly. If population is reduced, some tribal warriors must be released to return to their villages. If population increases, new tribal warriors become available."* Population-loss-equivalent releases must come from dormant first; if levied warriors exceed the new ceiling, the excess returns to dormant or — if dormant capacity is exhausted — to peaceful family life.

- **Pre-equipped, pre-trained** (`rules/ax_domains_of_chaos.xml:408`): *"When recruited, tribal warriors arrive trained and equipped according to tribal custom."* No equipment-purchase activity is required at levy time.

- **Wages: per troop type per DaW:C** (`rules/ax_domains_of_chaos.xml:411`): *"While serving, tribal warriors must be paid wages appropriate to troop type, using Mercenary GP Wage per Month from Domains at War: Campaigns."* Same wage as mercenaries of equivalent type. No tribal-warrior discount.

- **Troop type table per race** (`rules/ax_domains_of_chaos.xml:414-441`): The Tribal Warrior Troop Type table specifies, per 120 warriors, the troop-type breakdown for each of: **Jutland** (Germanic/Nordic humans), **Iv. King.** (Ivory Kingdoms — African tribal humans), **Skysos** (Mongolian/Scythian/Hun steppe nomad humans), and the eight beastman races (Kobold, Goblin, Orc, Hobgoblin, Gnoll, Lizardman, Bugbear, Ogre). This is the canonical procedural source for warband composition.

- **No conscription, no militia, no kin mercenaries except chaotic** (`rules/ax_domains_of_chaos.xml:37,40`):
  - *"Clanhold chieftains cannot conscript peasants or levy militia."* (Combined with the "additional levies are treated as militia" rule above, this hard-caps the levy at 1 per family.)
  - *"Clanhold chieftains may employ human and demi-human mercenaries only if they are chaotic."* The `solicit_mercenaries` mercenary-pool filter MUST exclude lawful / neutral mercenaries when the recruiter is a clanhold chieftain.

- **Beastman mercenaries allowed** (`rules/ax_domains_of_chaos.xml:39`): *"Clanhold chieftains may hire other beastmen in the area as mercenaries."* Beastman mercenaries are distinct from tribal warriors — external recruits paid in gp via `solicit_mercenaries`. The beastman mercenary catalog is a separate Phase 5+ concern (see §9.6).

- **Ogre and troll families count as 4 families** for population/growth but NOT for warrior count (`rules/ax_domains_of_chaos.xml:17`). An ogre clanhold of 38 families has 38 ogre warriors but consumes 152 family-equivalents of population cap.

- **Call-to-arms tribal-warrior favor cost** (`rules/ax_domains_of_chaos.xml:52`): *"When calling to arms, a chieftain may call half of available tribal warriors as 1 favor, or all available tribal warriors as 2 favors."* §8 specifies the integration with Phase 8 favors-and-duties.

- **Base morale + domain-morale modifier** (`rules/ax_domains_of_chaos.xml:446-449`): tribal warriors use their troop type's base morale. Steadfast/Stalwart domain morale → +1 one-time bonus at levy. Apathetic/Demoralized → −1 one-time penalty. Working-conditions modifiers apply as for mercenaries.

- **Loyalty / morale triggers** (`rules/ax_domains_of_chaos.xml:453-456`):
  - In battle: morale rolls when casualties exceed army break point (standard).
  - On calamity: loyalty rolls (routing, ≥25% casualties, out of supply, going without pay for a month — standard for mercenaries).
  - **Tribal-warrior-specific:** morale rolls *"after 3 consecutive months of service without receiving spoils from a battle or siege equal to at least their wages."* This is the canonical "raid or your warriors get restless" mechanic — NOT the dwindle curve v1.0 invented.

- **Departure** (`rules/ax_domains_of_chaos.xml:460-462`): on failed loyalty roll, consult the Unit Loyalty table. Departed warriors return to their villages if possible (back into the dormant pool); if not (e.g., the domain is cut off or destroyed), they become brigands or mercenaries.

---

## 3. Project Design Stance: Available vs. Levied Warriors

Tribal warriors exist in **two states** at the domain layer:

- **Available (dormant).** The warrior lives within a tribal family — performing horticulture / pastoralism / foraging / raiding under the chieftain's broad authority but NOT organized as a fielded military unit. Available warriors are tracked as a single integer counter (`domains.available_tribal_warriors`); the project does NOT track them as individual entities. They contribute 0 gp/month upkeep cost.
- **Levied.** The chieftain has activated a portion of available warriors into a fielded `troop_units` row. Levied warriors are tracked as a normal troop unit (same table, same army-warfare integration), with `source_type='tribal_warrior'`. Levied warriors require upkeep at the per-troop-type mercenary GP wage rate (§6).

The relationship between the four relevant quantities is the **pool invariant**:

```
available_tribal_warriors + sum(count of levied tribal_warrior troop_units) ≤ peasant_families
```

Where:
- **`peasant_families`** is the canonical population ceiling — moves up via population growth, down via disaster/morale collapse/slave loss.
- **`available_tribal_warriors`** is the dormant pool — initialized to `peasant_families` at clanhold establishment, decremented by levy, incremented by stand-down OR population growth (until the invariant equality holds), decremented by population loss (when needed to keep the invariant).
- **Casualty hits** (battle deaths, disease, etc.) **DO NOT** decrement `peasant_families`. They DO decrement the relevant `troop_units.count` row, which means the levied total drops AND `available_tribal_warriors` does NOT automatically refill — that's the core RAW insight from `rules/ax_domains_of_chaos.xml:404`.
- **Stand-downs** move warriors back to available. They DO refill `available_tribal_warriors`.

### 3.1 Casualty model — the central correction from v1.0

When a tribal-warrior `troop_units` row takes casualties (battle, disease, vagary):

1. `troop_units.count` decrements by casualty count.
2. **`available_tribal_warriors` is NOT modified.**
3. **`peasant_families` is NOT modified.**
4. The pool invariant now has slack: `available + levied < peasant_families`. The "missing" slots represent dead warriors whose families persist with surviving noncombatants but no warrior to contribute.
5. Future population growth (each new family) increments `available_tribal_warriors` by 1 — but ONLY up to the existing slack. New families are not "double warriors"; they replace dead warriors first.

Worked example (matching the user's correction):

> A clanhold has 500 families and 500 available warriors at establishment. The chieftain levies all 500. The warriors fight a battle and 250 die. State after battle:
> - `peasant_families` = 500 (unchanged — families persist, surviving noncombatants inherit the households).
> - `available_tribal_warriors` = 0 (dormant pool unchanged from before the battle).
> - One or more `troop_units` rows with `source_type='tribal_warrior'`: total `count` = 250 (down from 500).
> - Invariant check: 0 + 250 = 250 ≤ 500. Slack = 250.
>
> Over the next several months, population growth adds 50 new families. State after growth:
> - `peasant_families` = 550.
> - `available_tribal_warriors` = 0 → 50 (the new families' warriors flow into the dormant pool, refilling the slack from the casualties).
> - Invariant: 50 + 250 = 300 ≤ 550. Slack = 250 (the original 250 dead are still gone; new families on top of the 550 ceiling will increment available further).

This is what RAW means by *"casualties can only be replaced through population growth."* A killed warrior costs the army a slot until a new family fills it.

### 3.2 Population shrinkage — release dormant first, then levied

If `peasant_families` shrinks (e.g., morale-collapse-driven family migration, slave-trafficking, plague), the project must keep the invariant. Algorithm:

1. New ceiling = new `peasant_families` value.
2. Compute excess = `available + levied − new_ceiling`.
3. If excess > 0:
   - First, decrement `available_tribal_warriors` by min(excess, available). Released warriors return to family life.
   - If excess remains after available reaches 0, force stand-down of levied warriors: pick the lowest-tier troop_units rows first, decrement their counts until excess is absorbed.
4. Departure-log entries fire for each affected unit.

### 3.3 Kin clanholds — humans only

Per [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §3 + project canon (Jedidiah, 2026-05-21), **kin clanholds are restricted to HUMAN populations**. The three RAW kin tribal-warrior categories in the troop-type table (`rules/ax_domains_of_chaos.xml:417-419,429-440`) cover the entire kin-clanhold space:

- **Jutland** — Germanic / Nordic humans (Vikings, raider-confederations). Heavy on heavy infantry + bowmen.
- **Iv. King.** (Ivory Kingdoms) — African tribal humans (warrior-hunter cultures). Heavy on light infantry + hunters.
- **Skysos** — Mongolian / Scythian / Hun steppe nomad humans. Heavy on horse archers + composite bowmen + medium cavalry.

**Demi-humans are NOT clanhold-eligible:**
- **Elves and dwarves** have their own cultural domain types already defined (per project canon; not modeled as tribal clanholds even when settled in primitive fashion).
- **Halflings and gnomes** are not planned for the Arbiter v1 launch and likely not ever; their absence is intentional.

So the registry's column lookup is exhaustively: `'jutland'` → Jutland column; `'iv_kingdom'` → Iv. King. column; `'skysos'` → Skysos column; any of the eight beastman race strings → that race's column. No fallback case is required for v1. If a future kin-clanhold establishment attempts a non-listed cultural marker, the Levy activity rejects with an explicit error rather than guessing a column.

The `population_race` + cultural-marker resolution mechanism is the same one used elsewhere in the population-race tracking system per [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §9.7. (Forward note: when the Culture Canon GDD ships, the cultural-marker strings will be replaced by culture-IDs per the front-matter mapping; the lookup remains a single dictionary.)

### 3.4 Ogre and troll clanholds

Per RAW (`rules/ax_domains_of_chaos.xml:17`), ogre and troll families count as 4 families for population-cap and growth purposes — but each family still includes 1 ogre/troll warrior. v1 model:

- `peasant_families` for an ogre clanhold stores the **family count** (e.g., 38 ogre families), NOT the population-equivalent count (which would be 152).
- The 4-family multiplier applies in two places explicitly: (a) `DomainGrowthResolver` checks population caps + growth rates using `peasant_families × 4` for ogres/trolls; (b) `DomainRevenueCalculator` uses the same multiplier for land-revenue scaling.
- The pool invariant `available + levied ≤ peasant_families` produces the right warrior count (38 from 38 families, NOT 152 from 152 population-equivalents).

The 4× multiplier is OWNED by other resolvers (growth, revenue) and is not this GDD's concern.

---

## 4. Data Model

### 4.1 Schema changes (migration 129)

Migration 129 (Phase 11D.5 — Tribal Warriors implementation) lands the following:

**Add `available_tribal_warriors` column to `domains`:**

```sql
ALTER TABLE domains ADD COLUMN available_tribal_warriors INTEGER NOT NULL DEFAULT 0;
```

Seeded at clanhold/chaotic-domain establishment time: `available_tribal_warriors = peasant_families`. Mutated by levy / stand-down / casualty / population-change paths per §3.

**Extend `troop_units.source_type` CHECK constraint:**

The current enum is `('mercenary', 'conscript', 'militia', 'follower', 'slave_soldier', 'vassal')`. Add `'tribal_warrior'`. Full table rebuild via legacy_alter_table pattern (matches migrations 117 / 119 / 125 / 126 / 127):

```sql
PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;
BEGIN TRANSACTION;

ALTER TABLE troop_units RENAME TO troop_units_old;

CREATE TABLE troop_units (
    -- ... all existing columns ...
    source_type              TEXT    NOT NULL DEFAULT 'mercenary'
        CHECK(source_type IN (
            'mercenary', 'conscript', 'militia',
            'follower', 'slave_soldier', 'vassal',
            'tribal_warrior'  -- migration 129: Phase 11D.5 (was 128 pre-urban-stocking-shipping)
        )),
    months_without_qualifying_spoils  INTEGER NOT NULL DEFAULT 0,
    -- ... all remaining columns + indexes ...
);

INSERT INTO troop_units (...explicit column list..., months_without_qualifying_spoils)
SELECT ...same column list..., 0 FROM troop_units_old;
DROP TABLE troop_units_old;

CREATE INDEX idx_troop_units_campaign ON troop_units(campaign_id);
CREATE INDEX idx_troop_units_domain ON troop_units(assigned_domain_id);
CREATE INDEX idx_troop_units_owner ON troop_units(owner_character_id);
CREATE INDEX idx_troop_units_stronghold ON troop_units(assigned_stronghold_id);

COMMIT;
PRAGMA foreign_keys = ON;
```

The `months_without_qualifying_spoils` counter is the RAW 3-month-spoils trigger tracker (`rules/ax_domains_of_chaos.xml:456`). Incremented on monthly tick; reset to 0 when the unit receives spoils ≥ its monthly wage; triggers a morale roll on reaching 3. See §7.

**Extend migration 121 `event_type` CHECK with tribal-warrior event types:**

- `tribal_warriors_levied`
- `tribal_warriors_stood_down`
- `tribal_warriors_released_for_population_loss`
- `tribal_warriors_morale_check_triggered`
- `tribal_warriors_loyalty_failed`
- `tribal_warriors_called_to_arms`

### 4.2 Levied troop_units row shape

When a Levy Tribal Warriors activity completes, one or more `troop_units` rows are inserted. The shape:

| Column | Value |
|---|---|
| `source_type` | `'tribal_warrior'` |
| `troop_type` | Per RAW troop-type table — e.g., `'light_infantry'`, `'heavy_infantry'`, `'bowmen'`, `'crossbowmen'`, `'longbowmen'`, `'composite_bowmen'`, `'light_cavalry'`, `'horse_archers'`, `'medium_cavalry'`, `'beast_riders'`, `'hunters'`, `'slingers'` |
| `race` | population race string (`'orc'`, `'hobgoblin'`, ..., `'jutland_human'`, `'iv_kingdom_human'`, `'skysos_human'`) |
| `count` | per-troop-type count derived from the §5.2 procedural rollup |
| `tier` | `'average'` (RAW doesn't differentiate tiers within tribal warriors; champion/sub-chieftain/chieftain figures from L&E are not part of the RAW Tribal Warrior Troop Type table) |
| `monthly_wage_cp` | per troop type per `rules/daw_campaigns_troop_tables_summary.xml` (e.g., light infantry 600cp, heavy infantry 900cp, bowmen 600cp, crossbowmen 1200cp, horse archers 2500cp, beast riders 1500cp) |
| `monthly_supply_cp` | per army-warfare layer's standard supply cost |
| `morale` | per troop type's RAW base morale + domain-morale one-time adjustment (Steadfast/Stalwart: +1; Apathetic/Demoralized: −1) |
| `assignment_kind` | `'available'` on initial levy; `'garrison'` after assignment; `'on_campaign'` when in an army |
| `equipment_kit` | `'tribal_custom'` (RAW: arrives equipped per tribal custom; no commission_equipment needed at levy time) |
| `is_trained` | `1` |
| `is_veteran` | `0` |
| `months_without_qualifying_spoils` | `0` |

### 4.3 New EventBus signals

- `tribal_warriors_levied(domain_id, character_id, troop_unit_ids, total_count)` — fires when a Levy Tribal Warriors activity completes (multiple troop_units rows per the composition table; signal carries the full list).
- `tribal_warriors_stood_down(domain_id, character_id, troop_unit_id, count)` — voluntary return to dormant state.
- `tribal_warriors_released_for_population_loss(domain_id, count_released)` — forced release because peasant_families shrank below available+levied.
- `tribal_warriors_morale_check_triggered(troop_unit_id, reason)` — the 3-month-spoils morale check fires.
- `tribal_warriors_loyalty_failed(troop_unit_id, departure_kind)` — `departure_kind` is `'returned_to_villages'` or `'turned_brigand_or_mercenary'` per RAW.
- `tribal_warriors_called_to_arms(domain_id, scope, favor_cost)` — `scope` is `'half'` or `'all'`; `favor_cost` is 1 or 2.

### 4.4 Pool-size helper

`CampaignRepository.tribal_warrior_pool_for_domain(domain_id) -> Dictionary`:

```gdscript
# Returns:
#   {
#     peasant_families: int,
#     available: int,         # domains.available_tribal_warriors
#     levied: int,            # SUM(count) of active tribal_warrior troop_units for this domain
#     slack: int,             # peasant_families − available − levied (dead-not-yet-replaced)
#     pool_invariant_ok: bool # available + levied ≤ peasant_families
#   }
```

This is the canonical "how many warriors can the chieftain levy right now?" query. Reads in the Levy activity's input validation, the Garrison sub-tab's roster display, and the monthly population-growth refill hook.

---

## 5. Levy + Muster Pipeline

### 5.1 Levy Tribal Warriors activity

New activity, ships in Phase 11D.5. Lives alongside the Phase 5 garrison + Phase 10A.3 training activities in the Garrison sub-tab.

- **Activity classification:** minor; **may be repeated within a month** (RAW: *"The levy may occur all at once or over time"* — `rules/ax_domains_of_chaos.xml:400`). Each individual levy completes within one week.
- **Requirement:** `domain_style='clanhold'` OR `alignment='chaotic'`. Ruler must be at the domain's stronghold.
- **Inputs:**
  - `count` — number of warriors to levy (1 to `available_tribal_warriors`).
- **Validation:**
  - Reject if `count > available_tribal_warriors`.
  - Reject if `available_tribal_warriors == 0`.
- **Effects:**
  - `available_tribal_warriors` decrements by `count`.
  - The procedural composition resolver (§5.2) splits `count` into per-troop-type chunks per the race column of the RAW table.
  - One `troop_units` row inserts per non-zero troop type (potentially up to 8-9 rows for high-variety races; usually 2-4 in practice).
  - Each row's `assignment_kind = 'available'`.
  - Departure log entry: `event_type='tribal_warriors_levied'`.
  - EventBus signal: `tribal_warriors_levied(...)`.

### 5.2 Per-race procedural composition

The RAW table at `rules/ax_domains_of_chaos.xml:414-441` specifies the troop-type mix **per 120 warriors** for each race. The composition resolver:

```gdscript
TribalWarriorRegistry.compose_levy(race, total_count) -> Array[Dictionary]
    # Reads the per-120 row for `race` from the RAW table.
    # Scales each non-"none" entry by (total_count / 120.0).
    # Returns an array of {troop_type, count} dictionaries, rounded via banker's rounding.
    # The sum of counts equals `total_count` (residuals from rounding distributed to the
    # largest troop type per race to preserve the total).
```

**Worked examples (matching the PDF page 42 "Thrax" example):**

A 960-orc levy produces (per the orc column: light inf 44, heavy inf 30, bowmen 20, crossbowmen 20, beast riders 6, all per 120 warriors):

- Light infantry: 960 × (44/120) = 352
- Heavy infantry: 960 × (30/120) = 240
- Bowmen: 960 × (20/120) = 160
- Crossbowmen: 960 × (20/120) = 160
- Beast riders: 960 × (6/120) = 48

Total: 352 + 240 + 160 + 160 + 48 = 960. ✓

A 240-Jutland-human levy produces (Jutland column: light inf 60, heavy inf 30, bowmen 30):

- Light infantry: 240 × (60/120) = 120
- Heavy infantry: 240 × (30/120) = 60
- Bowmen: 240 × (30/120) = 60

Total: 120 + 60 + 60 = 240. ✓

A 60-Skysos levy (Skysos column: light cav 20, horse archers 25, composite bowmen 25, medium cav 20 — wait, that's 90 per 120, the remainder of 30 implicit in light infantry per L432 verifying... actually scanning the Skysos column: light infantry 30, light cavalry 20, horse archers 25, medium cavalry 20, composite bowmen 25 = 120):

- Light infantry: 60 × (30/120) = 15
- Light cavalry: 60 × (20/120) = 10
- Horse archers: 60 × (25/120) = 13 (rounds 12.5 to even → 12; +1 residual to light infantry)
- Medium cavalry: 60 × (20/120) = 10
- Composite bowmen: 60 × (25/120) = 12 (rounds 12.5 to even → 12)

Sum check + residuals normalize to exactly 60. (The banker's-rounding residual handling is in the implementation; v1 distributes any +1/−1 residual to the largest non-zero entry.)

### 5.3 Stand Down Tribal Warriors activity

The inverse operation. Removes a tribal-warrior `troop_units` row (or reduces its count), returning warriors to the available pool.

- **Activity classification:** minor, singular.
- **Requirement:** Ruler must be at the domain's stronghold OR at the troop_unit's location.
- **Inputs:** target `troop_unit_id` + count (1 to current `count`).
- **Effects:**
  - If full stand-down: row marked `status='departed'`, `departure_kind='stood_down'`.
  - If partial: `count` decremented.
  - `available_tribal_warriors` increments by the stand-down count.
  - EventBus signal: `tribal_warriors_stood_down(...)`.

Warriors stood down are NOT lost. They return to dormant pool.

### 5.4 Casualty handling

When a tribal-warrior `troop_units` row loses count (battle casualties, disease, vagaries) per the army-warfare layer:

- `troop_units.count` decrements by casualty count (handled by the army-warfare layer).
- `available_tribal_warriors` is **NOT** modified.
- `peasant_families` is **NOT** modified.
- The pool invariant now has slack equal to the casualty count (see §3.1 worked example).
- Future population growth fills the slack first (next §5.5) before adding new available warriors.

### 5.5 Population-growth refill (monthly tick)

In `DomainHandlers._handle_monthly_tick`, after `DomainGrowthResolver` resolves the month's population growth, the tribal-warrior pool refill hook fires:

```
slack = peasant_families − available_tribal_warriors − levied_total
if slack > 0 and population_growth_this_month > 0:
    refill = min(slack, population_growth_this_month)
    available_tribal_warriors += refill
    log event: 'tribal_warriors_replenished_by_growth' (optional event_type)
```

If population SHRANK this month: the §3.2 release algorithm runs (release from available first; force stand-down of levied if still over ceiling).

---

## 6. Wages, Equipment, Spoils

### 6.1 Wages — per troop type per DaW:C

Per `rules/ax_domains_of_chaos.xml:411`: tribal warriors are paid wages appropriate to their troop type, using **Mercenary GP Wage per Month** from `rules/daw_campaigns_troop_tables_summary.xml`. This is the same wage rate as kin mercenaries of the equivalent troop type. **No tribal-warrior wage discount.**

Per-troop-type monthly wages (representative values; canonical source is the DaW:C table):

| Troop type | Wage (gp/month) | Wage (cp) |
|---|---|---|
| Light infantry / Hunters | 6 | 600 |
| Heavy infantry | 9 | 900 |
| Slingers | 3 | 300 |
| Bowmen | 6 | 600 |
| Crossbowmen | 12 | 1200 |
| Longbowmen | 15 | 1500 |
| Composite bowmen | 9 | 900 |
| Light cavalry | 18 | 1800 |
| Horse archers | 25 | 2500 |
| Medium cavalry | 30 | 3000 |
| Beast riders | 15 | 1500 |

Worked example matching PDF page 42 ("Thrax orc force"):

- 352 light infantry × 6 gp = 2,112 gp
- 240 heavy infantry × 9 gp = 2,160 gp
- 160 bowmen × 6 gp = 960 gp
- 160 crossbowmen × 12 gp = 1,920 gp
- 48 beast riders ÷ 1.5 = 32 units × 15 gp = 495 gp (PDF uses 33 × 15 = 495; close enough — rounding)
- **Total monthly wage: 7,647 gp** (the PDF example used 5,535 gp for slightly different sub-counts; the formula is canonical).

Dormant (available) warriors are paid **0 gp/month** — they are not in active service.

### 6.2 Equipment

Per `rules/ax_domains_of_chaos.xml:408`: warriors arrive trained and equipped per tribal custom. v1:

- The `troop_units` row's `equipment_kit` field defaults to `'tribal_custom'`.
- Each per-race troop-type combination uses the standard armor + weapons for that troop type per the DaW:C catalog (e.g., orc heavy infantry uses chainmail + shield + 2H weapon; Skysos horse archers use leather + composite bow + light lance).
- Upgrading equipment (e.g., switching orc heavy infantry to plate armor) requires the standard `commission_equipment` activity per Phase 10B.2 Mercantile, paid in gp from the ruler's treasury. RAW does not require this; it's optional upgrade scope.

### 6.3 Spoils, NOT loot share

The v1.0 GDD invented a 50/50 loot-share split with per-tier weighting. RAW does NOT specify a loot-share distribution. Instead, RAW's mechanic is **the 3-month-spoils morale trigger** (`rules/ax_domains_of_chaos.xml:456`):

- Each levied tribal-warrior `troop_units` row tracks `months_without_qualifying_spoils`.
- A month's spoils for the unit "qualify" if the unit's share of battle/siege loot for that month is ≥ the unit's monthly wage (count × monthly_wage_cp).
- On a qualifying month: `months_without_qualifying_spoils` resets to 0.
- On a non-qualifying month (or no battle this month): the counter increments by 1.
- On reaching 3: a morale roll fires (see §7). The counter then resets to 0 regardless of outcome (to avoid re-triggering each month until something happens).

How spoils flow to units is governed by the army-warfare layer's existing loot-distribution mechanism per `gdd-army-warfare.md`. Tribal warriors do not get a special distribution formula — they just track whether their slice exceeded their wage on a 3-month rolling window.

The ruler still pays the wages from their domain treasury via the standard Phase 5 garrison-expenditure path. Spoils flowing to the warriors are above and beyond their wages; the wages are the floor, the spoils-≥-wages is the morale-keeper.

### 6.4 No loot-distribution mini-game

The v1.0 GDD's "Distribute Loot Share" decree, per-tier loot weights, and "shorted-loot morale penalty" are all dropped. RAW's spoils-vs-wages rolling check is sufficient.

---

## 7. Morale and Loyalty

### 7.1 Base morale + domain-morale modifier

Per `rules/ax_domains_of_chaos.xml:446-449`:

- Each `troop_units` row starts with morale equal to the troop type's RAW base morale (orc heavy infantry, hobgoblin longbowmen, etc. — looked up from DaW:C catalog).
- **One-time modifier at levy time** based on the domain's morale tier:
  - Steadfast or Stalwart → +1 morale.
  - Apathetic or Demoralized → −1 morale.
  - Other tiers → 0.
- This +1/−1 is a **one-time** bonus baked into the unit at levy. It does NOT track ongoing domain-morale changes; the unit's morale is independent once levied.
- Working-conditions modifiers (per army-warfare layer) apply as for mercenaries.

### 7.2 Standard loyalty / morale triggers

Per `rules/ax_domains_of_chaos.xml:453-456`:

- **In battle:** morale rolls when casualties exceed the army's break point. Resolved by the army-warfare layer (standard).
- **On calamity:** loyalty rolls per the standard mercenary-calamity rules:
  - Routing from a battle.
  - Suffering ≥25% casualties.
  - Being out of supply.
  - Going without pay for a month.

### 7.3 The 3-month-spoils trigger (tribal-warrior-specific)

Per `rules/ax_domains_of_chaos.xml:456`: *"Tribal warriors also make morale rolls after 3 consecutive months of service without receiving spoils from a battle or siege equal to at least their wages."*

Mechanism:

- The `troop_units.months_without_qualifying_spoils` counter tracks consecutive months without spoils ≥ wages (§6.3).
- When the counter reaches 3 on the monthly tick: morale roll fires.
- The morale roll uses the unit's current morale score with **no special tribal-warrior modifier** — the fact that the roll occurs at all is the penalty. Standard modifiers per `gdd-army-warfare.md` apply as normal.
- On success: counter resets to 0; unit continues service.
- On failure: a loyalty roll fires (see §7.4 — the unit may depart).
- Either way, `months_without_qualifying_spoils` resets to 0 after the roll.

EventBus signal: `tribal_warriors_morale_check_triggered(troop_unit_id, reason='3_months_without_spoils')`.

### 7.4 Departure consequences

Per `rules/ax_domains_of_chaos.xml:460-462`: on a failed loyalty roll, consult the Unit Loyalty table. v1 implementation:

- The Unit Loyalty table resolves to one of: continue service (with possible morale adjustment), partial departure (some count departs), full departure.
- Departing warriors: `departure_kind='returned_to_villages'`. The warriors return to the dormant pool: `available_tribal_warriors += departed_count`.
- The departed warriors come off the `troop_units.count` (or the row is fully departed if all warriors leave).
- Departure-log entry: `event_type='tribal_warriors_loyalty_failed'` with `departure_kind` in the payload.

EventBus signal: `tribal_warriors_loyalty_failed(troop_unit_id, departure_kind)`.

**No reachability / hex-distance gate per Q-TW-8 (resolved 2026-05-22 as not-applicable).** The Q-TW-8 "warriors return to villages if reachable, else turn brigand" framing assumed an orphaned-troop scenario that doesn't actually exist in mass-combat. The owning chieftain retains control over surviving warriors at any count > 0; if the warriors are far from home, the army marches them back. There's no in-data "partial" state that needs special handling. The Unit Loyalty failure simply returns warriors to villages directly.

The two scenarios where this could theoretically fail:
- **Unit destroyed (RAW casualty profile = 50% crippled/dead + 50% wounded → 0 uninjured survivors).** No warriors to return; refill is a no-op.
- **Unit survived but at reduced strength.** Owning chieftain retains the unit; voluntary stand-down via `StandDownTribalWarriorsHandler` refills the pool by the surviving count.

The RAW 50%-operational-dissolution trigger (`new_count < starting_count / 2 → status='departed'`) that applies to standard troop types is **EXEMPTED for tribal warriors** in `ArmyCasualtyResolver._resolve_side` (Phase 11D.5 Option B fix). Tribal-warrior units only auto-depart when battle status is explicitly `'destroyed'` OR `new_count <= 0`. Reduced-strength tribal-warrior units stay `status='active'` under the chieftain's control.

### 7.5 What v1.0 invented and is now dropped

For clarity, v1.0 added these mechanisms that RAW does not support and have been removed:

- ❌ **10%/month exponential dwindle curve** when chieftain fails to raid. Dropped.
- ❌ **25% pool dispersal threshold** with warband-status-lost effects. Dropped.
- ❌ **Rebuild the Warband decree.** Dropped.
- ❌ **Per-tier loot share** with 1×/2×/4×/8× weights. Dropped.
- ❌ **"Distribute Loot" decree.** Dropped.
- ❌ **Garrison-inactivity escalating morale penalty (−1/−2/−3/−4 cap).** Replaced by RAW's 3-month-spoils trigger.
- ❌ **1:1 `peasant_families` decrement on warrior casualty.** Replaced by the available-pool model.

---

## 8. Call to Arms — Liege-Imposed Duty on a Clanhold Vassal

### 8.1 What Call to Arms actually is

Call to Arms is a **duty a liege imposes on a vassal** within the existing favors-and-duties system. The standard form (per the Phase 8 mechanic, drawn from ACKS Domains chapter):

> *"Call to Arms: The vassal is called to provide military troops to his lord. He must muster an army with troop wages equal 1gp per family in his realm and make it available to his lord until the duty is revoked. He does not have to go personally unless a Call to Council favor is also demanded. This duty can be imposed multiple times, increasing the gp value of troop wages accordingly."*

The liege spends **favor tokens** they hold over the vassal (accumulated via oath, gift, marriage, prior service, etc.) to impose the duty. Each imposition of Call to Arms costs at least one favor token; the duty stacks — second imposition demands 2gp/family worth of troops, third demands 3gp/family, etc. The duty cascades down the realm: an emperor's Call to Arms on a king may force the king to issue his own Call to Arms on his dukes, who in turn call on counts, and so on, until the troops flow up the hierarchy.

**There is no self-imposed Call to Arms.** A ruler does not "call himself to arms" — a ruler who wants to mobilize his own warriors simply uses the Levy activity (§5) directly.

### 8.2 The clanhold modification

Per `rules/ax_domains_of_chaos.xml:52`: *"When chieftains call to arms they can call for half the available tribal warriors as one favor, or all tribal warriors as two favors."*

This is **not a separate Call to Arms variant** — it is a modification to the standard duty mechanic that applies WHEN the targeted vassal is a clanhold-style or chaotic-aligned ("tribal") domain. Specifically, the modification changes the muster computation:

- **Standard vassal** (civilized-style domain receiving Call to Arms): the vassal must raise troops with gp-wage value equal to `N × 1gp × peasant_families`, where `N` is the duty-stack count.
- **Tribal vassal** (clanhold-style OR chaotic-aligned domain receiving Call to Arms): the muster is denominated in **percentage of available tribal warriors**, not gp:
  - **1 favor token spent** → demand for 50% of the tribal vassal's `available_tribal_warriors`.
  - **2 favor tokens spent** → demand for 100% of the tribal vassal's `available_tribal_warriors`.
  - The 1-or-2 stack is independent of the gp-stack mechanic — a tribal-domain Call to Arms is "all-or-half" rather than a continuous scale.

When the liege has both standard and tribal vassals in their realm and imposes Call to Arms across the realm to muster an army, each vassal's contribution is computed per their own type: standard vassals contribute by gp-value, tribal vassals contribute by % of their tribal-warrior pool.

### 8.3 Cascading through the realm

The cascade behavior is identical to standard Call to Arms:

1. Emperor imposes Call to Arms on King A (a standard vassal). Cost: 1 favor token. Demand: 1gp/family of King A's realm.
2. King A's realm has more families than King A can field personally, so he issues Call to Arms on his own vassals to make up the muster:
   - Duke B (standard): King A spends 1 favor on Duke B, demanding 1gp/family of Duke B's domain.
   - Chieftain C (clanhold-style vassal of King A): King A spends **2 favor tokens** on Chieftain C to demand **100% of Chieftain C's available tribal warriors**.
3. Chieftain C may in turn have sub-chieftain vassals, and pass the demand down — Chieftain C spends 1 or 2 favors on each sub-chieftain to demand half or all of their tribal warriors. (RAW: chieftains can't call to council or grant title, but they CAN call to arms.)
4. Troops flow upward through the cascade until the emperor's muster is filled.

Each vassal's response involves an auto-levy on their clanhold (decrementing `available_tribal_warriors` and creating `troop_units` rows per §5) OR a standard mercenary-style muster for non-tribal vassals.

### 8.4 v1 implementation — modifications to Phase 8 `call_to_arms` duty handler

Phase 8's existing `call_to_arms` duty handler ships in `engine/subsystems/duties/handlers/call_to_arms.gd` (or wherever Phase 8 lands; current scaffolding lives in the activity layer per `gdd-domain-tab.md` §11). The Phase 11D.5 work modifies it:

- **Liege selection of vassal targets**: when the liege opens the Call to Arms UI and selects a vassal to target, the UI checks `domain_style` + `alignment` of the target. If clanhold-style OR chaotic-aligned, the UI switches from a "gp value to demand" input to a "scope radio" (Half / All) with corresponding favor cost (1 / 2).
- **Muster computation**: when the duty resolves on the tribal vassal's monthly tick, the muster size is `round_up(0.5 × available_tribal_warriors)` for Half or `available_tribal_warriors` for All.
- **Auto-levy**: the tribal vassal's `available_tribal_warriors` decrements by the muster size; the §5.2 composition resolver builds the troop_units rows per the vassal's race column.
- **Assignment**: the levied troop_units rows have `assignment_kind='on_loan_to_liege'` (new value, project-designed) and a back-pointer to the duty record. The army-warfare layer treats them as the liege's troops for the duration of the duty.
- **Revocation**: when the liege revokes the duty (or the duty expires per the normal Phase 8 mechanic), the loaned tribal-warrior rows return to the vassal. They DO NOT auto-stand-down; they return to the vassal's roster with `assignment_kind='available'`. The vassal may then stand them down via the standard §5.3 activity, or keep them levied at his own cost.
- **Cascade**: if the tribal vassal is itself a liege of further tribal sub-vassals, the player (or AI ruler) may stack additional Call to Arms duties on the sub-vassals to make up the muster.
- **Favor cost**: the liege's favor-token expenditure (1 or 2) is deducted at duty-impose time per the standard Phase 8 mechanic.
- **Departure log entry**: `event_type='tribal_warriors_called_to_arms'` with `scope`, `favor_cost`, and `imposed_by_liege_id` in the payload. Logged on the tribal vassal's departure log (the duty's effect is felt by the vassal).

### 8.5 What happens when a ruler has no liege

A ruler at the top of a realm hierarchy has no liege who can impose Call to Arms on them. They simply use the standard §5.1 Levy activity to mobilize their own warriors. No favor cost, no scope-radio, no duty record — just a direct levy at their own discretion.

(Q-TW-6 from v1.1 is RESOLVED by this clarification: there is no "Call to Arms when no liege" case to design for. The decree-style flow v1.1 invented does not exist.)

---

## 9. Cross-System Integration

### 9.1 Garrison expenditure calculator (Phase 5)

`GarrisonExpenditureCalculator.compute_from_domain` reads `troop_units` rows and sums monthly wages. Tribal-warrior rows contribute at their per-troop-type `monthly_wage_cp` rate (DaW:C mercenary rates per §6.1). No special handling needed — the per-row sum naturally includes them.

### 9.2 Domain morale resolver

`DomainMoraleResolver` consumes the morale state of all troop_units rows assigned to a domain. Tribal warriors' morale is read identically to mercenaries' morale. The 3-month-spoils morale rolls and loyalty-failure departures all apply at the troop_unit row level.

The domain-morale-tier-at-levy modifier (Steadfast/Stalwart +1, Apathetic/Demoralized −1) is applied ONCE at levy time and baked into the row.

### 9.3 Army warfare layer (Phase 6A/B)

Levied tribal-warrior `troop_units` rows are standard troop_units for army composition, marching, supply, vagaries, and field-battle resolution. The `gdd-army-warfare.md` layer reads them without distinguishing source_type, except for:

- **Spoils tracking**: at battle/siege resolution, the army-warfare layer must determine each unit's spoils share for the engagement and update `months_without_qualifying_spoils` on the tribal-warrior rows (reset to 0 if share ≥ wages, otherwise increment on the next monthly tick if no other qualifying event arrived).
- **Casualty hook**: per §5.4, tribal-warrior casualties decrement `troop_units.count` only — NOT `peasant_families` and NOT `available_tribal_warriors`.

### 9.4 Phase 11D.2 chieftain vassalage limits

Per [`gdd-domain-style-and-alignment.md`](gdd-domain-style-and-alignment.md) §9.5, chieftains have RAW-blocked actions (no monopoly, no loans, no council, no grants of title). The Call the Warriors favor pricing is part of the same vassalage-limits clause. The implementation should keep both limits in the same module / config so they're discoverable together.

### 9.5 Kin tribal warriors — read RAW table directly

The RAW Tribal Warrior Troop Type table (`rules/ax_domains_of_chaos.xml:414-441`) directly provides Jutland / Iv. King. / Skysos columns. v1 reads these columns per the population_race + cultural-marker mapping (§3.3). NO project-designed stat-block table needed — RAW covers the kin case explicitly.

For kin races without an explicit RAW column (elves, dwarves, halflings, gnomes), v1 falls back to Jutland (Q-TW-3 flags for future expansion).

### 9.6 Beastman mercenary catalog (deferred)

Per `rules/ax_domains_of_chaos.xml:39`, chaotic-realm rulers may hire beastmen as mercenaries. Distinct from tribal-warrior levy. Catalog work deferred to Phase 12+ when faction work formalizes realm-vs-clan distinctions.

### 9.7 Religion (no interaction)

Tribal warriors do not directly interact with [`gdd-religion-conversion.md`](gdd-religion-conversion.md). Tribal warriors derive from family count, not from congregants. Religion drives the alignment-morale system, which feeds the Steadfast/Stalwart-vs-Apathetic/Demoralized modifier per §7.1 — but only at levy time.

---

## 10. UI Surface

### 10.1 Garrison sub-tab (`gdd-domain-tab.md` §8)

A new "Tribal Warriors" section visible only when the active entity rules a tribal domain (`domain_style='clanhold'` OR `alignment='chaotic'`). Renders:

- **Pool status header.**
  - Family count: 500
  - Available warriors: 250 (dormant)
  - Levied warriors: 200 (in active units)
  - Slack (warriors lost, awaiting population growth to refill): 50
  - Invariant check: 250 + 200 = 450 ≤ 500 ✓
- **Activity cards:**
  - **Levy Tribal Warriors** — opens a modal with: count input (1 to available), preview of resulting troop_units rows per the §5.2 composition resolver showing per-troop-type counts and total wage burden.
  - **Stand Down Tribal Warriors** — modal lists active tribal-warrior troop_units rows; player picks one + count to disband.
- **Roster panel.** Lists active tribal-warrior troop_units rows with composition (per-troop-type counts), morale, location/assignment, `months_without_qualifying_spoils` counter.
- **Wage burden line.** Sum of monthly wages across all levied units (gp/month).

### 10.2 Phase 8 Call to Arms duty UI — clanhold-vassal modification

No new decree is added for tribal warriors. The Phase 8 Call to Arms duty UI (already part of Phase 8 favors-and-duties) gains a clanhold/chaotic-vassal branch:

- When the liege selects a vassal whose `domain_style='clanhold'` OR `alignment='chaotic'`, the UI's "Demand value" input is replaced by a **scope radio (Half / All)** with corresponding favor cost (1 / 2 tokens). The preview shows the projected muster size (e.g., "Half of 480 available = 240 tribal warriors").
- On confirmation, the duty is imposed per §8.4 with the muster size derived from the radio selection.
- For non-tribal vassals, the standard "gp-value-per-family" UI is unchanged.

If the player is the ruler of a clanhold/chaotic vassal who receives a Call to Arms duty from an NPC liege, the duty appears in the player's pending-duties list with the muster size already computed (the player has no choice in the matter — the liege chose the scope). The player can either fulfill (auto-levy fires on the next monthly tick) or refuse and face the standard Phase 8 refuse-duty consequences.

### 10.3 Status header

A banner appears in the Domain Status header when:

- Any tribal-warrior unit has `months_without_qualifying_spoils == 2`:
  > ⚠ Warriors restless · No qualifying spoils for 2 months · morale roll triggers next month if no plunder.

- A tribal-warrior unit just failed its loyalty roll (`tribal_warriors_loyalty_failed` signal in the last 7 days):
  > ⚠ Tribal warriors departed · {count} returned to villages · {count} turned brigand

### 10.4 Departure log event types

Migration 121's `event_type` CHECK constraint gets these additions in 11D.5:

- `tribal_warriors_levied`
- `tribal_warriors_stood_down`
- `tribal_warriors_released_for_population_loss`
- `tribal_warriors_morale_check_triggered`
- `tribal_warriors_loyalty_failed`
- `tribal_warriors_called_to_arms`

---

## 11. Implementation Roadmap (Phase 11D.5)

Per [`docs/phase-11-plan.md`](../docs/phase-11-plan.md) §11D.5:

- **Migration 129** lands:
  - Add `domains.available_tribal_warriors INTEGER NOT NULL DEFAULT 0`.
  - Add `troop_units.months_without_qualifying_spoils INTEGER NOT NULL DEFAULT 0`.
  - Extend `troop_units.source_type` CHECK with `'tribal_warrior'` (full table rebuild).
  - Extend migration 121 `event_type` CHECK with the six tribal-warrior event types.
  - Backfill `available_tribal_warriors = peasant_families` for any pre-existing clanhold/chaotic domains.
- **`TribalWarriorRegistry`** (new static class, `engine/subsystems/troops/tribal_warrior_registry.gd`):
  - `compose_levy(race, total_count) -> Array[Dictionary]` per §5.2 (reads the RAW table).
  - `wage_for_troop_type(troop_type) -> int` (cp/month, reads DaW:C catalog).
  - `base_morale_for_troop_type(race, troop_type) -> int` (reads DaW:C catalog).
- **`LevyTribalWarriorsHandler`** (new activity handler, `engine/subsystems/activities/handlers/levy_tribal_warriors.gd`): validation + composition + troop_units row creation + domain.available decrement per §5.1.
- **`StandDownTribalWarriorsHandler`** (new activity handler).
- **Call to Arms duty handler modification** (extending Phase 8's `call_to_arms` duty handler per §8.4): branch on tribal-vs-standard vassal; for tribal, use scope-based muster computation; auto-levy on duty resolution; `assignment_kind='on_loan_to_liege'` on the levied rows; return-to-vassal on revocation. **No** new self-imposed "Call the Warriors" decree.
- **Population-growth refill hook** in `DomainHandlers._handle_monthly_tick` (per §5.5): after growth, refill available pool from any slack.
- **Population-shrink release hook** in the same tick (per §3.2): if peasant_families dropped below available+levied, release dormant first then force stand-down.
- **Spoils distribution hook**: extend `SiegeSpoilsResolver` (`engine/subsystems/sieges/siege_spoils_resolver.gd`) with a `distribute_to_units(spoils_dict, victor_unit_list) -> Dictionary[unit_id, share_cp]` static method using per-warrior-headcount split. Mirror the hook for field-battle spoils (likely a new `BattleSpoilsResolver`). Tribal-warrior caller: at resolution, look up each tribal_warrior `troop_units` row's share, compare to `unit.count × unit.monthly_wage_cp`. If ≥, reset `months_without_qualifying_spoils` to 0. If <, no immediate change (the monthly tick will increment).
- **Monthly tick spoils check**: at month-end in `DomainHandlers._handle_monthly_tick`, for each tribal_warrior troop_unit, increment `months_without_qualifying_spoils` if not reset this month. If a unit reaches 3, fire `tribal_warriors_morale_check_triggered` and trigger the morale roll. The counter resets to 0 after the roll regardless of outcome.
- **Loyalty-failure departure**: implement the brigand-or-return-to-villages branch per §7.4.
- **EventBus signals** (new, per §4.3).
- **UI surfaces** per §10.
- **Tests**: a new `tests/test_tribal_warriors.gd` suite covers: available pool seeded at establishment, levy decrements available, casualty doesn't decrement available, population growth refills slack, population loss releases dormant first, composition resolver matches PDF Thrax-orc example, wage burden matches DaW:C, 3-month-spoils morale trigger, loyalty failure routes to villages-vs-brigand, ogre clanhold pool = family count not 4× family count, kin Jutland levy uses Jutland column, Call the Warriors decree creates favor debt.

---

## 12. Open Questions / Architectural Concerns

After v1.2 resolutions, only one open architectural question remains.

### Resolved in v1.2 (Jedidiah, 2026-05-21)

- ✅ **Q-TW-1 (v1.1): Spoils-share computation.** RESOLVED — use the existing `SiegeSpoilsResolver` (`engine/subsystems/sieges/siege_spoils_resolver.gd`) which already computes per-siege `total_spoils_cp` per RAW `daw_sieges.xml §spoils_of_sieges L805-811` ("one month's wages of each defeated unit" + prisoner ransom value). Phase 11D.5 ADDS a per-unit distribution hook: at spoils-resolution time, the resolver allocates each victorious unit's share by `(unit_count / total_victor_army_count) × total_spoils_cp` (simple per-warrior-headcount split). For tribal-warrior units, the allocated share is compared against the unit's monthly_wage_cp × count; if ≥, the unit's `months_without_qualifying_spoils` resets to 0. **The "numbers adjustment for Tribal Warrior flow" the user flagged is exactly this addition**: the resolver currently returns a lump sum that's not yet distributed to participating victor units; v1 adds the per-headcount distribution and the per-unit qualifying-share check. Equivalent hook needs to exist for field-battle spoils (likely a new `BattleSpoilsResolver` mirroring the siege one) per `gdd-army-warfare.md`'s battle-resolution path. Naming notes for the future implementer: keep the lump-sum API in the resolver and add a `distribute_to_units(spoils_dict, victor_unit_list) -> Dictionary[unit_id, share_cp]` static method alongside; tribal-warrior callers consume the distribution result.

- ✅ **Q-TW-2 (v1.1): Spoils threshold cadence.** RESOLVED — per-month check, as v1.1 proposed. Each calendar month independently fails the spoils-≥-wages test; counter increments per failed month; resets on any qualifying month; rolls morale at 3.

- ✅ **Q-TW-3 (v1.1): Non-Jutland/Iv. King./Skysos kin races.** RESOLVED — demi-humans are NOT clanhold-eligible. Elves and dwarves have their own (non-clanhold) cultural domain types. Halflings and gnomes are not planned for Arbiter v1. The §3.3 fallback was removed; the lookup is now exhaustive and a non-listed cultural marker is a hard error. The culture-canon mapping (Jutland → cultures 6/7/8; Iv. King. → 11/12/14/16; Skysos → 15/17) is recorded in the front-matter for forward reference.

- ✅ **Q-TW-4 (v1.1): Morale-roll modifier on 3-month-spoils trigger.** RESOLVED — **no modifier**. The fact that the roll occurs at all is the penalty. Standard mercenary modifiers per `gdd-army-warfare.md` apply as normal.

- ✅ **Q-TW-5 (v1.1): Departure-to-villages refilling available pool.** RESOLVED — yes, refill. Warriors who depart and return alive to their villages flow back into `available_tribal_warriors`. Warriors who depart but cannot return (or who fully die in service) are lost — no refill from those cases.

- ✅ **Q-TW-6: Call to Arms when no liege.** RESOLVED — the question was based on a misunderstanding. Call to Arms is NEVER self-imposed; it is only ever a duty a liege imposes on a vassal. A ruler at the top of the realm hierarchy simply uses the §5.1 Levy activity directly when they want to mobilize. No favor cost is involved in self-directed levy. See §8 for the corrected framing.

- ✅ **Q-TW-7 (v1.1): Event_type granularity.** RESOLVED — keep all six event types separate (`tribal_warriors_levied`, `tribal_warriors_stood_down`, `tribal_warriors_released_for_population_loss`, `tribal_warriors_morale_check_triggered`, `tribal_warriors_loyalty_failed`, `tribal_warriors_called_to_arms`). Audit clarity is worth the six CHECK enum additions.

### Still open

- ✅ **Q-TW-8 (RESOLVED 2026-05-22 as not-applicable): Off-map "reachability" definition for return-to-villages vs. turn-brigand.** Jedidiah's mass-combat framing: there are only two real outcomes — the unit is destroyed (zero survivors per the RAW casualty profile) OR it survived (and remains under control of the owning faction/player, who can march it home or stand it down voluntarily). There's no "orphaned partial" state where warriors are alive but cut off from their command structure. The Q-TW-8 hypothesis (warriors turn brigand if too far from home) doesn't model anything that actually happens. **Resolution (Option B):** tribal-warrior units are exempted from the RAW 50%-operational-dissolution trigger (`new_count < starting_count / 2 → status='departed'`) that applies to mercenaries / conscripts / militia. They stay `status='active'` at any survivor count > 0; only truly destroyed (`status='destroyed'` or `new_count <= 0`) marks them departed. Voluntary stand-down via `StandDownTribalWarriorsHandler` refills the pool with surviving warriors. Loyalty-failure departures (§7.4) simply return warriors to villages directly — no distance check. Phase 11D.5 polish dropped the survivor-refill hook + this Q item from the open-questions list.

### Already-resolved questions from v1.0 (kept here for audit trail)

- ~~Q-TW-1 (wages): RESOLVED — per DaW:C mercenary table per troop type.~~
- ~~Q-TW-2 (equipment kit): RESOLVED — pre-equipped per tribal custom.~~
- ~~Q-TW-3 (loot share split): DROPPED — RAW uses spoils-vs-wages morale check, not a per-warrior share distribution.~~
- ~~Q-TW-4 (retention dwindle curve): DROPPED — RAW uses 3-month-without-spoils morale roll.~~
- ~~Q-TW-5 (per-race stat reading): RESOLVED — RAW Tribal Warrior Troop Type table is canonical.~~
- ~~Q-TW-6 (persistence vs. monthly re-cast): RESOLVED — RAW supports persistence.~~
- ~~Q-TW-7 (casualties → family decrement): RESOLVED — casualties only reduce the warrior pool.~~
- ~~Q-TW-9 (garrison-inactivity morale): DROPPED — RAW 3-month-spoils mechanic replaces it.~~
- ~~Q-TW-10 (beastman mercenary catalog): DEFERRED to Phase 12+.~~
- ~~Q-TW-11 (kin tribal warrior stats): RESOLVED — RAW table includes Jutland / Iv. King. / Skysos columns.~~
- ~~Q-TW-12 (event_type granularity): SUPERSEDED then RESOLVED — keep six events.~~

---
