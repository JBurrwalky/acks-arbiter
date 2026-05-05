# GDD: Specialists Subsystem

**Authority:** HYBRID. Wage values, hiring terms, and the henchman-cap exemption come from `acore_equipment.xml §specialists`. The Pathfinder and Land Surveyor roles + duties + monthly availability come from `le_wilderness_lair_rules.xml §hirelings`. The numeric bonus values that specialists contribute to Phase 4 / Phase 5 wilderness resolvers are PROJECT-DESIGNED.
**Status:** Phase 6 v1 implemented (2026-05-04). Engine-side complete (catalog, hire/dismiss/wages, bonus aggregation, wired into all four wilderness resolvers). Hiring UI (settlement panel) deferred — programmatic hire works for tests and dev tooling.
**Depends on ACKS rules:** `acore_equipment.xml §specialists`, `le_wilderness_lair_rules.xml §hirelings`.
**Depends on project GDDs:** `gdd-lair-discovery.md` (Phase 4 — uses Pathfinder bonus on lair search + passive spot, Land Surveyor on assessments), `gdd-tracking.md` (Phase 5 — uses Pathfinder bonus on tracking throws).

---

## 1. Purpose

Specialists are non-adventuring monthly hires. They occupy a separate subsystem from henchmen and mercenaries — different table, different lifecycle, different UI. Phase 6 ships two wilderness scout types (Pathfinder + Land Surveyor); the catalog is extensible to other specialist categories (Alchemist, Sage, etc. from `acore_equipment.xml §specialists.specialist_details`) without schema changes.

---

## 2. ACKS Rules Constraints (Sacred)

### 2.1 Henchman cap exemption (`acore_equipment.xml §specialists.maximum_henchmen.exemption`)

> "Mercenaries and specialists do not count against this limit."

A character can hire arbitrary specialists alongside their (Charisma-modified) henchman cap of 4. Phase 6 enforces no upper bound on `specialists` rows per party.

### 2.2 Monthly fee (`acore_equipment.xml §specialists.general_hiring_terms`)

> "Specialists: Typically hired for a flat monthly fee."

Specialists are paid a flat wage per month. No treasure share, no rations, no morale, no advancement. Payment runs through the same PartyWallet flow that pays henchmen, but as a separate `process_monthly_wages` call on `SpecialistHireManager` (parallel to `HenchmanLifecycleManager.process_monthly_wages`).

### 2.3 Wilderness scouts (`le_wilderness_lair_rules.xml §hirelings.specialist[name="scout"]`)

| Type            | Wage          | Template        | Duty                              |
|-----------------|---------------|-----------------|-----------------------------------|
| Pathfinder      | 25 gp/month   | Pathfinder      | Search hexes for lairs            |
| Land Surveyor   | 25 gp/month   | Cartographer    | Assess the number of lairs in a hex |

> "Both scout types are hired on a monthly basis."
> "They are available in urban settlements in the same numbers as navigators."
> "Scouts expect protection while on duty… equal to the maximum number of lairs in the hex or hexes they are assigned to explore." *(deferred — see §6)*
> "Scouts attempt to evade wandering monsters."
> "They will not fight for their employer."
> "They will not enter lairs unless recruited as henchmen."

### 2.4 Specialist behavior in encounters

Per RAW: scouts **will not fight** and **attempt to evade** wandering monsters. v1 does not yet model this in the encounter pipeline (specialists don't have combat stats and don't appear on the combat roster). When the specialist hiring + wandering interaction lands in Phase 6.5, the EvasionResolver from Phase 5 is the natural mechanism.

### 2.5 Cartographer template / "Cartographer specialist"

The Land Surveyor IS a Cartographer-templated explorer (RAW: "Land surveyors are 1st level explorers with the Cartographer template"). The plan grouping "Pathfinder, Land Surveyor, Cartographer" (in `run-an-update-pass-greedy-duckling.md`) treated Cartographer as a separate kind, but RAW uses it as the proficiency template, not a distinct specialist. Phase 6 v1 ships TWO kinds (Pathfinder + Land Surveyor); a future "field cartographer who maps and improves navigation" could land as a third kind without schema changes — just extend the catalog and the `kind` CHECK constraint.

---

## 3. Project-Designed Elaborations

### 3.1 Bonus values (+4 each)

RAW does not quote a numeric bonus for Pathfinder / Land Surveyor assistance to throws. Phase 6 v1 grants +4 to match the natural Tracking / Land Surveying proficiency bonus a 1st-level Explorer with the appropriate template would have. Tunable per-kind via `SpecialistCatalog._DEFINITIONS`:

```
pathfinder    → +4 lair_search, +4 lair_search_passive, +4 tracking
land_surveyor → +4 surveying
```

A Pathfinder's bonus applies to **active** dedicated lair searches, **passive** travel-leg lair-spot checks, and tracking throws — RAW says the role is "search hexes for lairs" and Pathfinders are 1st-level explorers proficient in Tracking. The passive-spot bonus is a project-designed extension consistent with the role.

### 3.2 Stacking

Phase 6 v1 explicitly STACKS specialist bonuses (two Pathfinders → +8 to lair_search). RAW does not prohibit hiring multiples; the wilderness scout availability tables suggest a party may. Settlement availability typically caps scouts at 1d10 / 1d3 / 1d2 / 1 (rolled per market class) so the practical ceiling is set by the player's settlement choice, not by a code-level cap.

### 3.3 Two-month grace period for unpaid wages

RAW does not specify what happens when a specialist's monthly wage cannot be paid. v1: `SpecialistHireManager.process_monthly_wages` increments `unpaid_months` on insufficient funds. After two unpaid months the specialist closes "unpaid" automatically. Future polish: configurable grace period; Charisma-driven tolerance for late wages.

### 3.4 No morale / no loyalty

Specialists are at-will hires. There is no `henchman_state` row, no Loyalty score, no morale tracker. The lifecycle is just: hire → optionally dismiss / let depart from unpaid wages.

### 3.5 Settlement availability not yet enforced

RAW says scouts are "available in urban settlements in the same numbers as navigators" — drawn from the `acore_equipment.xml §specialists` availability table by Class I-VI market. v1 does not gate hiring on actual settlement market class — `SpecialistHireManager.hire(...)` accepts any settlement_id without validation. Phase 6.5 polish: settlement-class-driven availability, parallel to the existing henchman pool generator.

---

## 4. Implementation Map

| Concern | File |
|---|---|
| Catalog (kinds, wages, bonuses) | [specialist_catalog.gd](engine/subsystems/specialists/specialist_catalog.gd) |
| Hire / dismiss / monthly wages | [specialist_hire_manager.gd](engine/subsystems/specialists/specialist_hire_manager.gd) |
| Bonus aggregation across active specialists | [specialist_bonus_resolver.gd](engine/subsystems/specialists/specialist_bonus_resolver.gd) |
| Phase 4 `LairSearchResolver` consumes via `optional_specialist_bonus` parameter | [lair_search_resolver.gd](engine/subsystems/exploration/lair_search_resolver.gd) (Phase 4) — wired at call sites in `wilderness_handlers.gd` |
| Phase 4 `SurveyingResolver` consumes via `optional_specialist_bonus` parameter | [surveying_resolver.gd](engine/subsystems/exploration/surveying_resolver.gd) (Phase 6 added param) |
| Phase 5 `TrackingResolver` consumes via `optional_specialist_bonus` parameter | [tracking_resolver.gd](engine/subsystems/exploration/tracking_resolver.gd) (Phase 6 added param) |
| Wilderness handler call sites for lair_search / passive / surveying / tracking | [wilderness_handlers.gd](engine/subsystems/session/handlers/wilderness_handlers.gd) `_resolve_lair_search_activity`, `_passive_lair_check`, `_resolve_survey_activity`, `_handle_tracking_check` |
| Repository helpers | [campaign_repository.gd](engine/autoloads/campaign_repository.gd) `open_specialist`, `list_active_specialists`, `get_specialist`, `update_specialist`, `close_specialist` |
| DB schema | [053_specialists.sql](db/migrations/053_specialists.sql) |

---

## 5. Signals

| Signal | Emitted from | Listeners |
|---|---|---|
| `specialist_hired(party_id, data)` | `SpecialistHireManager.hire` on success | NotificationManager toast, future Notebook history panel |
| `specialist_dismissed(party_id, data)` | `SpecialistHireManager.dismiss` and unpaid-wage auto-dismiss | NotificationManager toast |
| `specialist_wages_processed(party_id, summary)` | `SpecialistHireManager.process_monthly_wages` | NotificationManager (when total_deducted > 0 or dismissals happened), wage badge refresh |

`data` payload keys are documented immediately above each `signal` declaration in `event_bus.gd`.

---

## 6. Deferred (Phase 6.5 / later)

* **Settlement hiring panel.** v1 ships a programmatic hire path (tests + dev console). The settlement market overlay UI (parallel to the henchman hiring panel) is the next polish — surfaces available specialists by class-and-day, lets the player commit funds, persists the row.
* **Settlement availability** (RAW: "same numbers as navigators"). Generate a per-month-per-settlement specialist pool keyed on market class.
* **Protection requirement.** RAW says scouts "expect protection… equal to the maximum number of lairs in the hex." Currently the protection requirement is not enforced on lair-search activities.
* **Specialist evasion in encounters.** RAW: "scouts attempt to evade wandering monsters" and "will not fight." When a wandering encounter triggers during a search, specialists should auto-flee via `EvasionResolver` rather than vanishing silently.
* **Wage-flow integration with the henchman scheduler.** v1 wages are processed by an explicit caller. Phase 6.5 should hook `SpecialistHireManager.process_monthly_wages` into the existing wages-processed scheduler the way henchmen are processed monthly.
* **Other specialist kinds.** `acore_equipment.xml §specialists.specialist_details` includes Alchemist, Animal Trainer, Armorer, Engineer, Healer, Mariner, Ruffian, Sage, Spellcaster — each with their own wage and effect. Phase 6's catalog data structure supports adding these without schema changes (just extend the `kind` CHECK constraint and add definitions).
* **Cartographer specialist.** A separate "field cartographer who maps and improves navigation" specialist that could grant bonuses to `getting_lost_check` rolls or generate enriched hex-map metadata.
* **Player-character specialists.** RAW notes that PCs with appropriate proficiencies "may serve as specialists." v1 does not yet expose this; would map a PC + proficiency into the SpecialistCatalog lookup pipeline.
