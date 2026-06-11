# GDD: Specialists Subsystem

**Authority:** HYBRID. Wage values, duties, hiring terms, availability dice, and the henchman-cap exemption come from `acore_equipment.xml §specialists` (`rules/acore_equipment.xml:663-992`). The Pathfinder and Land Surveyor roles + duties + availability come from `le_wilderness_lair_rules.xml §hirelings` (`rules/le_wilderness_lair_rules.xml:183-210`). The dual-path model, field-bonus values, commission service pricing/durations, and all UI are PROJECT-DESIGNED.
**Status:** v2.0 IMPLEMENTED (2026-06-11, migration 153) — **dual-path redesign per Jedidiah's ruling**: specialists are either RETAINED (hired to accompany the party) or COMMISSIONED (in-settlement service completing at a calendar tick, collected later); some kinds support both. Restructured from the Phase 6 v1 document (engine-side retain path, landed 2026-05-04); §2 sacred content carried forward verbatim, §2.6-2.8 appended. The full v2 build landed same-day: commission lifecycle, settlement guild hire panel, monthly wage tick, Notebook Specialists tab (single page with Retained + Commissions sections; sub-tabs if rosters grow), catalog expansion (sage, alchemist). §10 lists what remains deferred.
**Depends on ACKS rules:** `rules/acore_equipment.xml:663-668` (flat monthly fee); `rules/acore_equipment.xml:670-690` (2d6 hiring reaction — deferred); `rules/acore_equipment.xml:692-742` (availability by market class; specialist rows 709-728); `rules/acore_equipment.xml:816-820` (henchman-cap exemption); `rules/acore_equipment.xml:872-992` (specialist roster, duties, monthly pay); `rules/le_wilderness_lair_rules.xml:183-210` (scouts).
**Depends on project GDDs:** [gdd-lair-discovery.md](gdd-lair-discovery.md) (Pathfinder/Land Surveyor field bonuses; hired surveyor satisfies Survey eligibility per the 2026-06-10 ruling, making surveyors load-bearing for the §7 stronghold gate); [gdd-settlement-exploration-ui.md](gdd-settlement-exploration-ui.md) (guild PoI activity surface hosts the hire panel); [gdd-management-notebook.md](gdd-management-notebook.md) (tab architecture the Specialists tab plugs into).
**Implementing files:** `engine/subsystems/specialists/specialist_catalog.gd`, `specialist_hire_manager.gd`, `specialist_bonus_resolver.gd` (landed); v2 adds `specialist_commission_manager.gd`, `scenes/ui/settlement/specialist_hire_panel.gd`, `scenes/ui/notebook/tab_pages/specialists_tab_page.gd`, migration `153_specialist_commissions.sql`.
**Modifiable by Claude Code:** Yes — service pricing/durations, availability-roll mechanics, bonus values, and UI structure are engineering decisions. The dual-path split itself and the §2 RAW content are not.
**Last updated:** 2026-06-11

---

## 1. Purpose

Specialists are non-adventuring professional hires — scouts, sages, alchemists, healers — paid a flat monthly fee, exempt from the henchman cap, occupying a separate subsystem from henchmen and mercenaries (different table, different lifecycle, different UI).

**The dual-path model (Jedidiah, 2026-06-11).** A specialist engagement takes one of two shapes:

1. **Retained (accompanying)** — hired to come along: a land surveyor brought to assess hexes, a pathfinder scouting for lairs, a sage taken to investigate ruins. Retained specialists attach to the party, travel with it abstractly (no token, no rations bookkeeping, no combat presence), draw a monthly wage via PartyWallet, and contribute expertise wherever the party is.
2. **Commissioned (in-settlement)** — hired for a discrete service without being taken along: a sage researching a topic, an alchemist brewing a potion. The work is commissioned at a settlement guild, completes at a known calendar tick, and the party returns to collect the deliverable (report or item).

Kinds may support one or both paths (§4). The retain path's engine layer landed in Phase 6 (2026-05-04); v2 adds the commission lifecycle, the player-facing hiring surface, the monthly wage tick, and the Notebook Specialists tab.

---

## 2. ACKS Rules Constraints (Sacred)

### 2.1 Henchman cap exemption (`acore_equipment.xml §specialists.maximum_henchmen.exemption`, `rules/acore_equipment.xml:816-820`)

> "Mercenaries and specialists do not count against this limit."

A character can hire arbitrary specialists alongside their (Charisma-modified) henchman cap of 4. No upper bound on `specialists` rows per party.

### 2.2 Monthly fee (`acore_equipment.xml §specialists.general_hiring_terms`, `rules/acore_equipment.xml:663-668`)

> "Specialists: Typically hired for a flat monthly fee."

Specialists are paid a flat wage per month. No treasure share, no rations, no morale, no advancement. Payment runs through the same PartyWallet flow that pays henchmen, but as a separate `process_monthly_wages` call on `SpecialistHireManager` (parallel to `HenchmanLifecycleManager.process_monthly_wages`).

### 2.3 Wilderness scouts (`le_wilderness_lair_rules.xml §hirelings.specialist[name="scout"]`, `rules/le_wilderness_lair_rules.xml:183-210`)

| Type            | Wage          | Template        | Duty                              |
|-----------------|---------------|-----------------|-----------------------------------|
| Pathfinder      | 25 gp/month   | Pathfinder      | Search hexes for lairs            |
| Land Surveyor   | 25 gp/month   | Cartographer    | Assess the number of lairs in a hex |

> "Both scout types are hired on a monthly basis."
> "They are available in urban settlements in the same numbers as navigators."
> "Scouts expect protection while on duty… equal to the maximum number of lairs in the hex or hexes they are assigned to explore." *(deferred — see §10)*
> "Scouts attempt to evade wandering monsters."
> "They will not fight for their employer."
> "They will not enter lairs unless recruited as henchmen."

### 2.4 Specialist behavior in encounters

Per RAW: scouts **will not fight** and **attempt to evade** wandering monsters. Not yet modeled in the encounter pipeline (specialists don't have combat stats and don't appear on the combat roster). When the specialist hiring + wandering interaction lands, the EvasionResolver from Phase 5 is the natural mechanism. Project generalization: ALL retained specialists are non-combatants with no lair/dungeon presence.

### 2.5 Cartographer template / "Cartographer specialist"

The Land Surveyor IS a Cartographer-templated explorer (RAW: "Land surveyors are 1st level explorers with the Cartographer template"). The plan grouping "Pathfinder, Land Surveyor, Cartographer" (in `run-an-update-pass-greedy-duckling.md`) treated Cartographer as a separate kind, but RAW uses it as the proficiency template, not a distinct specialist. A future "field cartographer who maps and improves navigation" could land as a third kind without schema changes — just extend the catalog and the `kind` CHECK constraint.

### 2.6 Specialist roster, duties, and monthly pay (`rules/acore_equipment.xml:872-992`)

| Specialist | Monthly pay | RAW duty | Lines |
|---|---|---|---|
| Alchemist | 250gp | Assists mages in potion creation; may research new potions as a 5th-level mage at twice base time and cost | 877-884 |
| Animal Trainer | 25–250gp | Taming/behavior training; ≤6 animals at a time | 885-899 |
| Armorer | 75gp | Produces 40gp/month of arms; maintenance 1 per 60 troops | 900-912 |
| Engineer | 250gp | Plans/oversees large construction | 913-920 |
| Healer / Physicker / Chirurgeon | 1/2/4 gp per day per patient | Bed-rest care +1d3 hp/day; physicker/chirurgeon non-magical cures on 18+/14+ | 921-935 |
| Mariner (rower/sailor/navigator/captain) | 3/6/25/100gp | Ship crew roles | 936-944 |
| Ruffian (carouser/footpad/reciter/spy/thug) | 6–125gp | Muscle and hijinks | 945-959 |
| Sage | 500gp | Consulted for information; difficult questions may require extra research costs; the Judge decides obscurity and wrong-answer chance | 960-966 |
| Spellcaster | varies | Casting for hire by market class and spell level (availability table 979-991) | 967-991 |

> "The list is not exhaustive; the Judge may create more specialists using proficiency rules." (`rules/acore_equipment.xml:873`)

### 2.7 Availability by market class (`rules/acore_equipment.xml:692-742`, specialist rows 709-728)

Each specialist type has a per-month availability dice expression by settlement market class I–VI. v2-relevant rows:

| Type | I | II | III | IV | V | VI |
|---|---|---|---|---|---|---|
| Alchemist | 1d10 | 1d3 | 1 | 1 (33%) | 1 (15%) | 1 (5%) |
| Sage | 1d6 | 1d2 | 1 (65%) | 1 (15%) | 1 (5%) | None |
| Scouts (= Mariner–Navigator row per `rules/le_wilderness_lair_rules.xml:197-200`) | 5d10 | 1d12 | 1d6 | 1d2 | 1 (60%) | 1 (45%) |

### 2.8 Hiring reaction roll (`rules/acore_equipment.xml:670-690`)

RAW negotiates hires via 2d6 + employer CHA (refuse-and-slander through accept-with-élan). **v2 defers this** — hires auto-accept at listed wage (§10).

---

## 3. Project-Designed Elaborations (retain path — Phase 6, carried forward)

### 3.1 Bonus values (+4 each)

RAW does not quote a numeric bonus for Pathfinder / Land Surveyor assistance to throws. v1 grants +4 to match the natural Tracking / Land Surveying proficiency bonus a 1st-level Explorer with the appropriate template would have. Tunable per-kind via `SpecialistCatalog._DEFINITIONS`:

```
pathfinder    → +4 lair_search, +4 tracking
land_surveyor → +4 surveying
```

*(2026-06-10 update: the v1 passive travel-leg lair-spot was removed with the lazy-placement rewrite — see [gdd-lair-discovery.md](gdd-lair-discovery.md) §10 — so `lair_search_passive` no longer has a call site; the catalog constant remains, harmless.)*

*(2026-06-10 ruling: a hired Land Surveyor also SATISFIES Survey eligibility when no party member has the proficiency — the specialist makes the throw at base, with no self-assist +4 and no strenuous penalty. See [gdd-lair-discovery.md](gdd-lair-discovery.md) §4.2.)*

### 3.2 Stacking

Specialist bonuses STACK (two Pathfinders → +8 to lair_search). RAW does not prohibit hiring multiples; the availability tables (§2.7) set the practical ceiling, not a code-level cap. When a hired surveyor is the Survey THROWER, their own +4 is excluded (no self-assist); additional hired surveyors still assist.

### 3.3 Two-month grace period for unpaid wages

RAW does not specify what happens when a specialist's monthly wage cannot be paid. `SpecialistHireManager.process_monthly_wages` increments `unpaid_months` on insufficient funds; after two unpaid months the specialist closes "unpaid" automatically. Future polish: configurable grace period; Charisma-driven tolerance.

### 3.4 No morale / no loyalty

Specialists are at-will hires. There is no `henchman_state` row, no Loyalty score, no morale tracker. Lifecycle: hire → optionally dismiss / let depart from unpaid wages.

### 3.5 Wage timing

No up-front charge on hire; the first wage debits on the next monthly tick (§6.3). RAW says only "flat monthly fee" — billing in arrears keeps hiring friction low and matches the v1 row shape (`last_paid_round = -1` until first payday).

---

## 4. The Dual-Path Model (v2)

Each catalog kind declares which paths it supports; a kind may support one or both. Kinds whose services other subsystems already model are NOT absorbed here — the catalog records an `owned_by` marker so the hire panel can point the player at the right surface.

| Kind | Retain (accompany)? | Commission (in-settlement)? | v2 status |
|---|---|---|---|
| pathfinder | Yes — +4 lair search / tracking in the field | No (duty is inherently field work) | Retain live (Phase 6) |
| land_surveyor | Yes — +4 surveying; makes the Survey throw for surveyor-less parties | No | Retain live (Phase 6) |
| sage | Yes — travels to investigate in the field (v2 is flavor/forward-compat; no field call sites yet) | Yes — consult a question / research a topic → report | **v2 build** |
| alchemist | No in v2 (RAW duty is lab work) | Yes — brew a potion → item | **v2 build** |
| engineer | No | `owned_by` stronghold construction ([CommissionPipeline] engineer counts) | Modeled elsewhere |
| ruffians | No | `owned_by` syndicate/hijinks system | Modeled elsewhere |
| spellcaster | No | `owned_by` settlement spell offers (`settlement_poi_spell_offers`) | Modeled elsewhere |
| mariners | No | `owned_by` ships/crew system | Modeled elsewhere |
| armorer, animal trainer, healers | — | — | Deferred (§10) |

---

## 5. Commission Path (v2)

### 5.1 Lifecycle

```
1. COMMISSION  → at a guild PoI: pick kind + service (+ subject text where applicable),
                 pay cost_cp up front via PartyWallet,
                 row created with completes_at_round = now + duration
2. IN PROGRESS → status derived LAZILY: ready iff party_time >= completes_at_round
                 (no scheduled event; no per-tick bookkeeping)
3. READY       → shown in the Specialists tab; collectible only while the active
                 party is in the commission's origin settlement
4. COLLECTED   → deliverable granted:
                 report → dialog + journal entry; item → inventory_items row
```

- **Payment is up front, in full** (the specialist buys materials and commits the time). Cancellation refunds nothing in v2 (no cancellation surface ships).
- The commissioned specialist never joins the party; no `specialists` row is created for a commission.
- The result is rolled/fixed AT COMMISSION TIME and stored in `result_payload` (deterministic collection; saves don't reroll deliverables).

### 5.2 v2 service catalog (PROJECT-DESIGNED — flagged for play-test calibration)

RAW gives monthly retainers, not per-service prices. v2 prices services as the pro-rated retainer for the time committed:

| Service id | Kind | Cost | Duration | Deliverable |
|---|---|---|---|---|
| `sage_consult_question` | sage | 125gp (≈1 week of the 500gp/month retainer) | 7 days | Report (answer text; journal entry) |
| `sage_research_topic` | sage | 500gp (one month retained) | 30 days | Report (research summary; journal entry) |
| `alchemist_brew_healing` | alchemist | Potion of Healing market value (magic item catalog) | 7 days | Item (`potion_of_healing` to party inventory) |

RAW's sage uncertainty ("the Judge decides... the chance a wrong answer is given") and difficult-question surcharges are deferred — v2 reports are truthful, flat-priced, and the report TEXT is a placeholder summary until the LLM narration layer phrases them. The alchemist brew list is intentionally a single entry until the magic-item usage session lands.

### 5.3 Data model

```sql
-- Migration 153
CREATE TABLE IF NOT EXISTS specialist_commissions (
    commission_id         TEXT    PRIMARY KEY,
    campaign_id           TEXT    NOT NULL REFERENCES campaigns(id),
    party_id              TEXT    NOT NULL REFERENCES parties(id),
    settlement_id         TEXT    NOT NULL,
    kind                  TEXT    NOT NULL,            -- catalog kind ('sage', 'alchemist')
    service_id            TEXT    NOT NULL,            -- catalog service id
    service_label         TEXT    NOT NULL DEFAULT '',
    subject               TEXT    NOT NULL DEFAULT '', -- player-entered topic/question
    cost_cp               INTEGER NOT NULL DEFAULT 0,
    commissioned_at_round INTEGER NOT NULL DEFAULT 0,
    completes_at_round    INTEGER NOT NULL DEFAULT 0,
    result_kind           TEXT    NOT NULL DEFAULT 'report'
        CHECK(result_kind IN ('report', 'item')),
    result_payload        TEXT    NOT NULL DEFAULT '', -- report text / item_key
    collected             INTEGER NOT NULL DEFAULT 0 CHECK(collected IN (0, 1)),
    collected_at_round    INTEGER NOT NULL DEFAULT 0
);
```

Mirrors the equipment `commissions` table shape (settlement-scoped, ready-at/picked-up) with party scoping and a generic deliverable. The retain path keeps the existing `specialists` table (migration 053) unchanged.

---

## 6. Availability, Hiring Surface, and Wages (v2)

### 6.1 Availability rolls

Per settlement × kind × calendar month: roll the §2.7 dice for the settlement's market class **deterministically** (seeded RNG keyed on campaign_id + settlement_id + kind + month index, so reopening the panel doesn't reroll), minus retains/commissions already made there that month. "1 (65%)" cells resolve the percentage from the same seed. "None" cells (Sage at class VI) are simply unavailable — go to a bigger town. Supersedes v1's §3.5 "availability not yet enforced."

### 6.2 Settlement guild hire panel

The guild PoI's "Hire Specialists" activity (already listed in `activity_panel.gd`) emits a new `specialist_hiring_requested(poi)` signal, routed by `SettlementExploreState` exactly like the henchman `hiring_requested` flow. The panel lists catalog kinds with availability counts; per kind:

- **Retain** (kinds with the retain path): hires into the active party at the listed monthly wage (billing in arrears per §3.5).
- **Commission** (kinds with services): pick the service, enter subject text where applicable, confirm; PartyWallet debits immediately; row created.
- `owned_by` kinds render as informational rows pointing at their surface.

### 6.3 Monthly wage tick

A `Timekeeping.month_changed` listener (SessionRunner-owned, connected on session load) calls `SpecialistHireManager.process_monthly_wages(party_id, employer_id, now)` for every party with active specialists. Employer = first living, active PC in the party (v1 of payroll attribution; revisit with the henchman payday work — §10). Existing unpaid-grace behavior (§3.3) applies unchanged.

---

## 7. Notebook Specialists Tab (v2)

New top-level tab ("Specialists", after Henchmen — tab strip goes 5+4) following the Henchmen-tab pattern (status header + sub-tabs):

- **Retained** sub-tab: rows of kind / name / wage / hired-from / unpaid-months badge, with a Dismiss action (at-will per §3.4; confirmation dialog).
- **Commissions** sub-tab: rows of service / settlement / subject / status (`In progress — ready day N` / **Ready** / `Collected`), with a **Collect** button enabled only while the active party's current settlement matches the commission's settlement. Collecting a report opens it in a dialog and writes a journal entry; collecting an item adds it to party inventory.
- Status header: retained count + monthly wage total; open commission count.
- Empty state explains both paths and points at settlement guilds.

---

## 8. Signals

| Signal | Emitted from | Listeners |
|---|---|---|
| `specialist_hired(party_id, data)` *(exists)* | `SpecialistHireManager.hire` | Specialists tab, toast |
| `specialist_dismissed(party_id, data)` *(exists)* | dismiss / unpaid auto-close | Specialists tab, toast |
| `specialist_wages_processed(party_id, summary)` *(exists)* | monthly wage tick | Specialists tab, toast on deductions/dismissals |
| `specialist_commissioned(party_id, data)` *(new)* | `SpecialistCommissionManager.commission` | Specialists tab, toast |
| `specialist_commission_collected(party_id, data)` *(new)* | `SpecialistCommissionManager.collect` | Specialists tab, toast, Journal |

`data` payload keys are documented immediately above each `signal` declaration in `event_bus.gd`.

---

## 9. Implementation Map (v2)

| Concern | File | Action |
|---|---|---|
| Catalog: dual-path flags, services, availability rows, owned_by markers, sage + alchemist kinds | `specialist_catalog.gd` | EXTEND |
| Hire / dismiss / monthly wages (retain) | `specialist_hire_manager.gd` | KEEP (landed) |
| Bonus aggregation | `specialist_bonus_resolver.gd` | KEEP (landed) |
| Commission lifecycle | (new) `engine/subsystems/specialists/specialist_commission_manager.gd` | CREATE |
| Commission persistence | `campaign_repository.gd` + `db/migrations/153_specialist_commissions.sql` | CREATE |
| Monthly wage tick | `session_runner.gd` `Timekeeping.month_changed` listener | CREATE |
| Hire panel | (new) `scenes/ui/settlement/specialist_hire_panel.gd`; `activity_panel.gd` routes `hire_specialists` → `specialist_hiring_requested`; `settlement_explore_state.gd` opens the panel | CREATE |
| Specialists tab | (new) `scenes/ui/notebook/tab_pages/specialists_tab_page.gd`; register in `notebook.gd` TAB_PAGE_SCRIPTS + `notebook_tab_strip.gd` TAB_ORDER | CREATE |
| `kind` CHECK constraint | migration 153 widens `specialists.kind` CHECK to add 'sage' (alchemist is commission-only; no specialists rows) | MIGRATE |

---

## 10. Deferred / Open Questions

- **Service pricing calibration (PROJECT-DESIGNED):** §5.2 prices are pro-rated retainers; RAW doesn't price one-off services. The alchemist brew at full market value intentionally equals shop price — the value is guaranteed availability, not discount. Play-test.
- **Hiring reaction roll** (§2.8) — v2 auto-accepts. Adding the 2d6+CHA negotiation (with refuse-and-slander reputation consequences) is a clean future layer over the hire panel.
- **Sage wrong-answer uncertainty** — RAW Judge discretion; v2 reports are truthful. Eventual design likely wants a hidden reliability roll narrated by the LLM layer.
- **Commission-ready notification** — lazy status means no proactive "your research is ready" toast; v2 relies on the tab. A `day_changed` check is cheap polish.
- **Henchman payday remains unwired project-wide** — the Henchmen tab's "wages auto-deduct on payday" is aspirational. §6.3 wires SPECIALIST wages only; hanging henchman wages on the same listener is the obvious follow-up, not absorbed here.
- **Protection requirement** (§2.3) — scouts expect mercenary protection scaled to hex lair counts; unenforced.
- **Specialist evasion in encounters** (§2.4) — auto-flee via EvasionResolver when a wandering encounter triggers during specialist-assisted activities.
- **Healers / animal trainers / armorers** — healers want the rest/recovery system, trainers the trained-creatures system, armorers the domain economy. Path assignment when integrated.
- **Retained sage field hooks** — no mechanical field call sites yet; retained sages are flavor/forward-compat until ruins-investigation content lands.
- **Player-character specialists** — RAW notes PCs with appropriate proficiencies may serve as specialists; unexposed.
- **Cartographer kind** (§2.5) — possible third scout kind granting `getting_lost_check` bonuses.
