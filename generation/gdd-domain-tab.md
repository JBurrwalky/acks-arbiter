# GDD: Domain Tab

> **2026-05-15 currency-precision note:** All gp-suffixed money identifiers in this GDD have been renamed to their `_cp` equivalents in the engine — the project's base currency is cp (1 gp = 100 cp). Examples: `treasury_cp`, `deferred_maintenance_cp`, `pending_investment_cp`, `tax_rate_cp_per_family`, `liturgy_rate_cp_per_family`, `tithe_rate_cp_per_family`, `repression_cp_per_family_this_month`, `revenue_cp`, `expenses_cp`, `net_income_cp`, `cp_amount` (ledger). Banker's rounding only fires on fractional cp. Treat any remaining `_gp` references in pseudocode below as documentation drift.

**Document type:** Game Design Document (Project-designed, improvable)
**Authority:** Subordinate to `gdd-management-notebook.md`. Authoritative on the Domain tab's content (Status header, sub-tab structure, per-class sub-tab matrix, activity-execution model, lifecycle interactions). Defers to `gdd-stronghold-construction.md` for stronghold-construction details (the Domain tab consumes that GDD's outputs and surfaces them; it does not redefine construction mechanics). Defers to `gdd-troops-tab.md` for troop unit lifecycle (the Domain tab references troop units assigned to a domain's garrison but does not redefine unit mechanics).
**Status:** Draft v1.6 — pending review
**Depends on:** `gdd-management-notebook.md` v1.5+, `gdd-ui-architecture.md` v2.10+, `gdd-ui-shared-services.md` v1.2+, `gdd-character-tab.md` v1.6+, `gdd-party-tab.md` v1.4+, `gdd-henchmen-tab.md` v1.3+, `gdd-troops-tab.md` v2.3+, `gdd-stronghold-construction.md` (current draft).

**Sibling / interfacing documents:**
- `gdd-management-notebook.md` §3.4 — establishes this as notebook tab #6 (primary column, between Troops #5 and Journal #7). M-key remains Troops; Domain tab uses **D**.
- `gdd-character-tab.md` §3 — entity strip and active-entity model. The Domain tab follows the same per-entity activation pattern: it scopes to the current active entity (PC or humanoid henchman), defaulting to the player's active PC at notebook open. The entity-type dropdown is restricted to **PCs** and **Humanoid Henchmen** only — Mercenary Officers, Trained Animals, and Vehicles cannot rule domains.
- `gdd-henchmen-tab.md` §5 / §7 — vassal-henchman cross-tab activation. Right-click on a humanoid henchman row → "Manage Domain" (when that henchman is a vassal ruler) cross-activates the Domain tab on that henchman per `gdd-management-notebook.md` §4.4.
- `gdd-party-tab.md` §1.1 — LLC analogy. Domain rule semantics: PC and Humanoid Henchman are the only roles that can hold a domain. Mercenaries (Independent Contractors) cannot rule. Animals and vehicles cannot rule.
- `gdd-troops-tab.md` §3 / §4 — troop unit roster. Domain tab's Garrison sub-tab references troop units assigned to a domain's garrison, with cross-activation to the Troops tab for unit-level management.
- `gdd-stronghold-construction.md` (current) — stronghold structure catalog, archetypes, commission pipeline, NPC stronghold generation, claiming existing structures. Domain tab's Stronghold sub-tab presents a status-and-summary view over this GDD's data and offers cross-activation to the construction commission flow.
- `gdd-settlement-exploration-ui.md` — Settlement Panel handles location-tied market activities (buy/sell merchandise, hire mercenaries, solicit merchants/passengers/shippers). Domain tab cross-references the Settlement Panel for those activities; it does not host them.
- `gdd-realtime-scheduler.md` — monthly campaign cycle per `ax_campaign_play.xml` §monthly_cycle. Domain tab subscribes to scheduler boundary events for monthly resolution (revenue collection, expense payment, morale rolls, growth, encounter throws).
- `gdd-unified-log-panel.md` — domain-related log entries (revenue collected, morale roll outcomes, encounters fired, vassal favors/duties, stronghold-construction completion) emit through `EventBus.log_entry_added` per the standard log schema.
- `acore_axioms_strongholds_and_domains.xml` — sacred rules for domain sizes, classifications, acquisition, land value, peasant population, followers arrival, growth, revenue/expenses, realms/vassals, titles, tribute, favors-and-duties, morale (base + current), urban settlements.
- `ax_campaign_play.xml` — sacred rules for the monthly campaign cycle, activity framework (major/minor/trivial × singular/restricted/ongoing × strenuous/unstrenuous), and per-category activity definitions (adventuring / divine / domain / magical / mercantile / professional / syndicate).
- `ax_domain_level_encounters.xml` — sacred rules for domain encounter throws, dangerous borders, dungeon-monster morale impact, encounter reactions (hostile / unfriendly / neutral / mercantilist / friendly), mass-combat resolution.
- `ax_domains_of_chaos.xml` — sacred rules for chaotic domains, beastman clanholds, tribal warriors, slave-labor demographics. Drives the chaotic-domain branch in v1 from foundation per Jedidiah's Q6 resolution.
- `daw_armies_recruitment.xml` — sacred rules for army sources (mercenaries, conscripts, militia, followers, slave soldiers, vassal troops). Garrison sub-tab consumes these.
- `daw_campaigning_armies.xml` — sacred rules for the weekly campaign procedure when a domain ruler initiates `military_campaign`. Domain tab surfaces military-campaign initiation and consumes the resulting domain-state changes.
- `daw_sieges.xml` — sacred rules for siege blockade / reduction / assault. Encounters & Threats sub-tab surfaces siege state when a domain is besieged.
- `acore-setting-construction-rules.xml` — sacred rules for settlement market classes, demographic baselines, NPC ruler levels by domain tier. Setting-generation outputs feed the Domain tab.
- `acore-campaign-general-and-magic-research.xml` — sacred rules for magic research (consumed by the class-specific sub-tab for arcane casters).
- `acore_core_classes.xml`, `acore_demihuman_classes.xml`, `acore_campaign_classes.xml`, `pc_classes_1.xml` through `pc_classes_5.xml`, `ax_venturer_class.xml` — class definitions including per-class `<stronghold_and_followers>` data: structure type, follower composition, follower cost rules, follower loyalty/morale rules. The class sub-tab matrix (§12.1) consumes these.
- `pc_followers_tables_rules.xml` — class follower equipment tables for follower auto-generation when followers arrive.

**Scope of this document:**
- Per-entity Domain tab activation model (active-entity-driven, mirroring Character tab)
- Domain Status header (visible across all sub-tabs)
- Nine sub-tabs: Overview / Stronghold / Garrison / Realm / Treasury & Ledger / Activities / Class-Specific / Encounters & Threats / Departure Log
- Per-class concern matrix and the class-conditional §7 sub-tab content
- Activity-execution architecture: hybrid notebook-as-source-of-truth with greyed location-gating + travel shortcut + future location panels deferred to v1.1+
- Pre-9th-level handling
- Chaotic-domain support from foundation
- Multi-domain handling (PC ruling personal domain plus vassal domains held by henchmen)
- Realm aggregation at the personal domain level
- Lifecycle interactions: domain establishment, classification advancement / regression, growth, monthly resolution, encounter response, conquest, abandonment, ruler death
- Cross-tab interactions and notification routing
- Multi-party scope (per-party state, per-PC ownership)
- Empty-state with class-tailored acquisition guidance
- Migration plan from current zero-Domain-UI state
- Performance considerations
- Open questions and build sequencing

**Out of scope:**
- Stronghold construction details — covered by `gdd-stronghold-construction.md`. The Domain tab's Stronghold sub-tab summarizes and cross-activates that surface; it does not duplicate construction mechanics.
- Settlement Panel content — covered by `gdd-settlement-exploration-ui.md`. Mercantile activities (buy/sell, solicit merchants, etc.) live there.
- Henchman lifecycle — covered by `gdd-henchmen-tab.md`. Domain tab presents a vassal-henchman summary in the Realm sub-tab and cross-activates the Henchmen tab for individual lifecycle management.
- Troop unit lifecycle — covered by `gdd-troops-tab.md`. Domain tab's Garrison sub-tab presents a per-domain garrison view and cross-activates the Troops tab for unit-level management.
- DaW mass-combat resolution UI — that is the future combat-tactical surface (post-Phase H+). Domain tab feeds units INTO that surface via the Garrison sub-tab and consumes post-battle outcomes (casualties, morale events, occupation, pillaging) back into the Encounters & Threats and Treasury sub-tabs.
- Hijink field-execution UI — the Syndicate class-specific block surfaces hijink configuration, queue, and outcome history; the actual perpetration-of-the-hijink narrative flow (target selection beyond domain bounds, infiltration sub-system, etc.) is its own future surface. The Domain tab's Syndicate block handles ordering / planning / laying-low / outcome readback.
- Magic research field-execution flow — the Magical Research block surfaces research configuration and progress; the actual roll-resolution at the end of a research project (with success/failure consequences, magic-research throw modifiers, and any narrative beats) is handled by the future Magic Research surface or the existing notebook activity-execution flow.
- Mass-combat tactical surface (DaW battles) — Domain tab does not host tactical UI. Future combat-tactical surface owns that.
- Stronghold defense battle map generation — covered by `gdd-stronghold-construction.md` §11.
- Setting / world generation — covered by `gdd-setting-generation.md`. Domain tab consumes generation output for hex-level land value, demographic baselines, and political-entity context.

---

## 1. Purpose and design intent

The Domain tab is the canonical surface for managing the player's territorial and political reach — strongholds, peasants, garrisons, vassals, revenues, expenses, encounters, and class-specific high-level activities tied to a base of operations. It is the surface where the game shifts from "adventurer" play to "ruler" play, typically beginning at character level 9.

**Design intent:**

- **Per-entity, active-entity scoped (Q1 resolution).** The Domain tab follows the Character tab's pattern: the tab content is the active entity's domain. The entity strip at the top (per `gdd-management-notebook.md` §6.1) supports navigation between PCs and humanoid henchmen. Trained animals, vehicles, and mercenary officers do not appear in the entity-strip dropdown for this tab — none can rule a domain.
- **PCs and humanoid henchmen are the only domain rulers.** This implements the LLC analogy from `gdd-party-tab.md` §1.1: Members (PCs) hold their own domains; Employees (humanoid henchmen) can hold vassal domains as part of a higher-level PC's realm. Independent Contractors (mercenaries) and Property (animals, vehicles) cannot rule.
- **Personal Domain focus (Q3 resolution).** When the active entity is a PC or henchman, the Domain tab shows that entity's *own* personal domain. To inspect or manage a vassal domain held by a henchman, the player switches the active entity to that henchman. The Realm sub-tab provides a vassal-domain *list* and aggregate at the active entity's level, but per-vassal management requires switching active entity. This keeps the per-entity scope rule clean and matches how PCs and their henchmen are already navigated in the Character tab.
- **Pre-9th-level support (Q2 resolution).** Per `acore_axioms_strongholds_and_domains.xml` §before_ninth_level, characters of 8th level or less do not attract followers or peasants — but they *can* still acquire an existing domain, build a stronghold, hire mercenaries, and invest gp to attract peasants. The Domain tab supports this pre-9 path: an entity who owns a domain pre-9 sees the full Domain tab content, with the auto-follower-attraction system disabled and a banner indicating *"Followers and peasants begin arriving at level 9. You may still build, invest, and hire mercenaries."* An entity who does not yet own a domain sees the empty state with class-tailored acquisition guidance.
- **Chaotic domain support from foundation (Q6 resolution).** Per `ax_domains_of_chaos.xml`, chaotic-aligned PCs may opt into chaotic-domain mechanics at domain establishment. The Domain tab supports this branch in v1 from the start: the establish-domain flow includes the chaotic-or-normal toggle for chaotic-aligned PCs; subsequent mechanics (beastman followers, tribal warrior levy, halved investment value, +2gp garrison cost, urban revenue capped at 7gp/family, no class V via investment) apply automatically per the chaotic-domain ruleset. This is foundational because retrofitting it later would require schema migrations across population, garrison, urban, and revenue paths.
- **Class-aware UI (Jedidiah's overarching constraint).** Each class has different domain concerns. The Domain tab respects this in three ways: (1) the empty-state acquisition guidance is tailored to the active entity's class per Q7; (2) the Class-Specific sub-tab (§12) surfaces only the high-level activities and resources relevant to the active entity's class; (3) class-gated activities elsewhere in the tab are suppressed or disabled when the active entity's class lacks the relevant capability (e.g., a mage's Garrison sub-tab does not surface `oversee_troop_training` since that activity requires fighter-progression-class).
- **Activity-execution hybrid (Q8 resolution).** The Domain tab is the master inspection-and-execution surface. Every class-applicable activity surfaces here with current state, parameters, and history. Activities that require physical presence at a specific structure are *configurable* in the notebook from anywhere but *executable* only when the active entity is at the required location. Greyed-out execute buttons display a tooltip explaining the location requirement and offer a "Plan travel to [location]" shortcut. v1.1+ may add location-context panels (Stronghold-Adjacent Panel, modeled on the existing Settlement Panel) as ergonomic shortcuts; the notebook remains source of truth.
- **Cross-tab clarity, not duplication.** Stronghold construction details live in `gdd-stronghold-construction.md`. Henchman lifecycle lives in `gdd-henchmen-tab.md`. Troop unit lifecycle lives in `gdd-troops-tab.md`. Settlement-tied activities live in the Settlement Panel. The Domain tab presents *summary readouts* of those systems and offers *cross-activation* into them; it does not redefine their mechanics. This matches the established pattern of the other notebook tabs.
- **Source-of-truth deterministic engine.** Per `CLAUDE.md` Core Principle "Build mechanically, narrate retroactively," all domain mechanics are deterministic engine state. The Domain tab is a presentation layer over that state. Monthly resolution rolls (revenue, morale, growth, encounters) are deterministic given seed + state. LLM narration is *additional* — the Unified Log's Narration tab may show prose for domain events, but the mechanical entries (combat, roll, system) are always emitted alongside.

**Non-goals:**

- The Domain tab does NOT redefine any ACKS rule. Every domain-mechanical claim cites a specific XML file in `rules/`. Project-designed elements (sub-tab structure, activity-execution model, empty-state copy, the Lightblessed Wonderworker stronghold rules per Q5) are explicitly tagged "Arbiter-specific design" in their respective sections.
- The Domain tab does NOT host the stronghold construction commission pipeline. That is owned by `gdd-stronghold-construction.md` §5. The Domain tab's Stronghold sub-tab includes a "Commission new structure" button that cross-activates the construction commission flow.
- The Domain tab does NOT host the DaW mass-combat tactical resolution surface. The future combat-tactical surface owns that. The Domain tab feeds units INTO it via the Garrison sub-tab and consumes outcomes back via Encounters & Threats and Treasury & Ledger.
- The Domain tab does NOT auto-resolve any monthly cycle activity without player consent. Monthly resolution is a scheduled scheduler-tick event; the player may pre-set automatic policies (e.g., "always pay garrison from treasury on payday") but the engine never silently makes domain-affecting decisions for the player. Pre-set policies are explicit, visible in the Treasury & Ledger sub-tab, and toggleable per monthly resolution.

---

## 2. Tab integration with the notebook

Per `gdd-management-notebook.md` §3.4, the Domain tab is tab #6 in the primary column ("the band"), positioned between Troops (#5) and Journal (#7).

**Invocation:**
- Toggle key: **D** (mnemonic: Domain).
- Cross-tab activations:
  - **Henchmen tab Roster** → right-click on a humanoid henchman row → "Manage Domain" (only when that henchman is a vassal ruler) → cross-activate Domain tab on that henchman per `gdd-management-notebook.md` §4.4.
  - **Realm sub-tab vassal list** (within the Domain tab itself) → click a vassal name → cross-activate Domain tab on the vassal-henchman.
  - **Character tab Status sub-tab** → "Open Domain Tab" button on the active entity's domain summary card → switch tab while keeping active entity.
  - **Troops tab Roster** → right-click on a unit assigned to a domain garrison → "View in Domain" → cross-activate Domain tab Garrison sub-tab on the unit's domain owner.
  - **Settlement Panel** mercantile flows → cross-activate Domain tab Treasury sub-tab to surface the resulting revenue/expense entry.
  - **Stronghold Construction commission completion** → cross-activate Domain tab Stronghold sub-tab to highlight the newly-completed structure.
  - **Domain encounter notification** (HUD toast) → action click cross-activates Domain tab Encounters & Threats sub-tab.
  - **Domain morale critical notification** (e.g., morale falls to Demoralized or below) → action click cross-activates Domain tab Overview sub-tab.

The Domain tab uses the standard notebook page area (vellum) per `gdd-management-notebook.md` §3.2.

---

## 3. Per-entity scope and active-entity model

### 3.1 Active entity drives the tab

Per Q1 resolution (option c): the Domain tab opens for the *active* entity, like the Character tab. The entity strip at the top of the page area (per `gdd-management-notebook.md` §6.1) provides navigation between PCs and humanoid henchmen.

**Entity-type dropdown** (leftmost element of the entity strip per `gdd-management-notebook.md` §6.1): for the Domain tab, restricted to:
- **PCs** (default selection)
- **Humanoid Henchmen**

Trained Animals, Vehicles, and Mercenary Officers do NOT appear in the dropdown when the Domain tab is the active tab. None of those entity types can rule a domain per ACKS RAW (Mercenary Officers are unit leaders not landholders; animals and vehicles are property, not agents). When the player switches to the Domain tab from another tab (e.g., from Character tab) while the active entity is a non-domain-eligible type, the tab auto-switches the active entity to the player's "preferred" PC (the highest-level domain-holding PC, or the active PC at session start if none hold a domain).

### 3.2 Empty-state vs. populated state

**Active entity holds a domain** → full Domain tab content, sub-tabs populated with the entity's domain data.

**Active entity does NOT hold a domain** → empty-state page with class-tailored acquisition guidance (per Q7 resolution and §22 Empty-state). Some sub-tabs may still have meaningful content even without a domain — e.g., a magic-research class can still access the Magical Research class block as a "preparation" surface for when they acquire a sanctum, with most actions disabled until a sanctum exists. The empty-state details which sub-tabs are usable in the no-domain state per §22.

### 3.3 Vassal henchman handling

When the active entity is a humanoid henchman who is a vassal ruler, the Domain tab shows that henchman's *personal domain* (which is a vassal domain within the player's PC's realm). The Realm sub-tab on the henchman's Domain tab shows any sub-vassals the henchman has of their own (henchmen-of-henchmen).

This enables the natural drill-down: PC's Domain tab → Realm sub-tab → click vassal → switch active entity to vassal-henchman → Domain tab shows vassal's domain → Realm sub-tab shows sub-vassals → drill further if desired.

The "domain-tab vs. henchmen-tab" responsibility split is clean: Henchmen tab manages the henchman as a *person* (their loyalty, wages, lifecycle, equipment); Domain tab manages the henchman *as the holder of a domain* (their stronghold, their domain's revenue, their vassal management). Both surfaces interact via cross-tab activation.

### 3.4 Per-entity state persistence

Per `gdd-management-notebook.md` §4.1, the Domain tab's per-tab substate stores per-entity state:

```
per_tab_substate[Domain] = {
  active_entity_type: "pc" | "humanoid_henchman",
  active_entity_id: String,
  per_entity_substate: {
    [entity_id]: {
      active_subtab: "overview" | "stronghold" | "garrison" | "realm" | "treasury" | "activities" | "class_specific" | "encounters" | "departure_log",
      sub_tab_filters: Dictionary,
      sub_tab_sort: Dictionary,
      sub_tab_scroll_position: Dictionary
    }
  }
}
```

Per-entity state allows the player to leave the Domain tab on the Garrison sub-tab for one henchman and the Realm sub-tab for another, and find each restored on entity switch.

Per `gdd-management-notebook.md` §4.2, this state persists across notebook open/close and across save-game cycles, but is not part of the save itself when the notebook is closed (notebook is closed at save by procedural guarantee).

---

## 4. Sub-tab structure

The Domain tab has nine sub-tabs (TabBar at the top of the content area, below the Domain Status header). Per Q4 resolution: Overview merges the originally-separate Population & Growth content; the Class-Specific sub-tab (§12) surfaces ONLY class-specific concerns; universal activities live in §11.

### 4.1 Sub-tab list

1. **Overview** (default on first activation per session per entity) — Domain Status summary + composition (PC families count by hex, urban families if any, demographic breakdown) + recent growth/decline + land value summary + alignment/religion + classification status + headline morale band
2. **Stronghold** — owned structure(s), sufficiency vs. minimum, maintenance status, pending construction projects, cross-activation to commission new construction
3. **Garrison** — troop units assigned to this domain, faithful-followers count, militia/conscript/tribal-warrior availability, garrison cost compliance, additional-troops repression and morale-bonus configuration
4. **Realm** — vassal domain list, tribute flows in/out, favors/duties tracker (per `acore_axioms_strongholds_and_domains.xml` §favors_and_duties), realm aggregates, current title display, tribute efficiency calculator
5. **Treasury & Ledger** — monthly revenue and expense detail, unpaid-expenses alerts, last-12-months income history, monthly auto-pay policies, gp accumulators (e.g., construction commitments, investments)
6. **Activities** — universal and proficiency-gated domain category activities per `ax_campaign_play.xml` §domain (administer_domain, issue_decree, conscript_troops, levy_militia, hire_mercenaries, manage_henchmen, oversee_investment, oversee_construction, supervise_construction, military_campaign, etc.). Class-specific domain activities are NOT surfaced here — they live in §12.
7. **Class-Specific** (label varies by class — e.g., "Faith" for divine casters, "Magical Research" for arcane casters, "Trade" for venturers, "Syndicate" for thief/assassin/nightblade, "Garrison Training" for fighter-progression classes, "Bardic Patronage" for bards) — class-conditional content surfacing only the high-level activities that are gated to the active entity's class. A class with multiple applicable buckets (e.g., Bladedancer = divine + fighter-progression; Lightblessed Wonderworker = arcane + divine) sees stacked content blocks within this single sub-tab. The sub-tab does NOT appear at all if the active entity's class has no class-specific high-level activities (e.g., a base 0th-level commoner would not see this sub-tab — though commoners do not rule domains).
8. **Encounters & Threats** — domain encounter log per `ax_domain_level_encounters.xml`, dungeon-monster morale impact (per §dungeons), dangerous-borders configuration, bandit alerts (when current morale ≤ −2), siege state when applicable per `daw_sieges.xml`, invasion / occupation / pillage status
9. **Departure Log** — chronological history of the domain's significant events of loss: classification regression, lost holdings, defeats, abandonment, ruler change, conquest by another power. Permanent record analogous to the Henchmen tab Departure Log

### 4.2 Sub-tab order and tab strip

The TabBar is rendered horizontally below the Domain Status header. With nine sub-tabs the strip may be wider than the page area; per `gdd-ui-shared-services.md` standard TabBar behavior, overflow is handled by horizontal scroll or wrap as appropriate.

The Class-Specific sub-tab (strip position 7; full content spec in §12 of this GDD) renders with its class-specific label inline (e.g., "Faith" / "Magical Research" / "Syndicate"). When the active entity's class has no class-specific sub-tab content, the sub-tab is hidden entirely — the strip renders eight sub-tabs in that case rather than rendering a placeholder.

### 4.3 Default sub-tab on entity activation

On first activation of the Domain tab for a given entity in a session, the Overview sub-tab is shown. On subsequent activations within the session, the last-active sub-tab for that entity is restored from `per_entity_substate`.

### 4.4 Class-Specific sub-tab visibility logic

The Class-Specific sub-tab (strip position 7) appears for active entities whose class has at least one applicable bucket from the matrix in §12.1. The buckets are:

- **Faith** — divine casters (Cleric / Priestess / Shaman / Dwarven Craftpriest / Witch / Bladedancer / Lightblessed Wonderworker). Detection: class_powers contains `divine_casting` OR `spell_research_and_minor_item_creation`.
- **Magical Research** — arcane casters AND divine casters with full research (Mage / Warlock / Elven Courtier / Elven Enchanter / Elven Spellsword / Elven Nightblade / Darkblood Ruinguard / Lightblessed Wonderworker / Cleric / Priestess / Shaman / Dwarven Craftpriest / Witch). Detection: class_powers contains `arcane_casting` OR `arcane_casting_in_armor` OR `spell_research`. Per Q11 [RESOLVED 2026-05-10].
- **Trade** — Venturer. Detection: class_powers contains `stronghold_guildhouse`.
- **Syndicate** — Thief / Assassin / Elven Nightblade (RAW class-id allowlist matching `acore-campaign-hijinks.xml` §hijinks-eligibility per Q14 [RESOLVED 2026-05-11]). Bards explicitly excluded by RAW. Detection: class_id in `{thief, assassin, elven_nightblade}`.
- **Bardic Patronage** — Bard only (per Q14 [RESOLVED 2026-05-11]). Surfaces the two Bard-specific class powers: Chronicles of Battle aura (`hireling_inspiration` L5+) and Solicit Followers (`hall` L9+). Detection: class_id == "bard".

**Per Q14 [RESOLVED 2026-05-11], the prior "Garrison Training" bucket is REMOVED.** Troop training (`train_troops`, `oversee_troop_training`, `inspect_troops`) is proficiency-gated on **Manual of Arms** (per ACKS Core proficiency list; ranks 1-2 enable light/heavy infantry, combined with Riding enables light/heavy cavalry, combined with Weapon Focus (bows & crossbows) enables crossbowmen / bowmen / longbowmen, all together enables horse archers / cataphract cavalry) or an equivalent class power, NOT on class membership. Many classes — including Cleric and Bladedancer — can take Manual of Arms and train troops. These activities now surface in the **Garrison sub-tab (§8)** with proficiency-based eligibility checks. Fighter-flavored classes that previously appeared under Garrison Training (Fighter, Paladin, Anti-Paladin, Barbarian, Explorer, Vaultguard, Delver, Fury, Elven Ranger) have NO Class-Specific bucket — the tab is hidden for them entirely (they manage troops via the Garrison sub-tab).

A class falling into multiple buckets (e.g., Cleric = Faith + Magical Research; Lightblessed Wonderworker = Faith + Magical Research) sees stacked content blocks within the single Class-Specific sub-tab. The sub-tab label takes the form *"Class Activities"* generically, OR is dynamically labeled per primary bucket if only one applies (e.g., a pure Mage's tab is labeled "Magical Research"; a Cleric's tab is labeled "Class Activities" because it has Faith + Magical Research stacked; a Bard's tab is labeled "Bardic Patronage").

Rendering details per §12.

---

## 5. Domain Status header

A slim summary header fixed at the top of the page area, **visible across all nine sub-tabs**.

### 5.1 Layout

```
+---------------------------------------------------------------------+
| Eastmarch  ·  Borderlands  ·  6 hexes  ·  142 fam · Loyal (+1)      |
| Stronghold: 24,500/22,500 ✓   Garrison: 2gp/fam ✓   Treasury: 1,840 |
+---------------------------------------------------------------------+
```

Two compact rows:

**Row 1 — Identity and headline state:**
- **Domain name** (player-assigned, project-designed UI — name editing in Overview sub-tab; never persists empty so the header always has a label, defaulting to e.g. "[Class] Stronghold" or "Untitled Domain" until named)
- **Classification** — Civilized / Borderlands / Wilderness per `acore_axioms_strongholds_and_domains.xml` §classification, color-coded by `UiPalette.classification_color` (Theme variants `classification_civilized` / `classification_borderlands` / `classification_wilderness` to be declared in `gdd-ui-shared-services.md` §4.3). For chaotic domains per `ax_domains_of_chaos.xml`, append a chaotic indicator badge (e.g., "Borderlands · Chaotic")
- **Territory size** — total 6-mile hexes in the domain (e.g., "6 hexes"). For sub-hex domains (a single 1.5-mile hex), show "1 small hex" or similar disambiguating label
- **Population** — total peasant family count (per `acore_axioms_strongholds_and_domains.xml` §peasants_and_followers); format compact (e.g., "142 fam" / "1,240 fam" / "12,500 fam")
- **Current morale** — band name (Rebellious / Defiant / Turbulent / Demoralized / Apathetic / Loyal / Dedicated / Steadfast / Stalwart per `acore_axioms_strongholds_and_domains.xml` §effects_of_morale) + signed score in parentheses; color-coded by `UiPalette.morale_color_for_band` (Theme variants `morale_rebellious` through `morale_stalwart` to be declared)

**Row 2 — Operational status:**
- **Stronghold** — total stronghold value vs. minimum required, with sufficiency indicator. Format: "{actual}/{required} {checkmark or warning}". Checkmark for full sufficiency, half-warning for ≥1/2 minimum, warning for ≥1/4 minimum, critical for less than 1/4 — per `acore_axioms_strongholds_and_domains.xml` §insufficient_stronghold and the −1 / −2 / −3 base morale penalties
- **Garrison compliance** — current monthly garrison spend per family vs. required minimum (Civ 2gp / Bord 3gp / Wild 4gp per `acore_axioms_strongholds_and_domains.xml` §garrison and §classification_modifiers). Same checkmark / warning / critical indicator
- **Treasury** — current available gold belonging to this domain ruler attributable to the domain (per the project-designed treasury model — see §10 Treasury & Ledger sub-tab for the data model). Compact gp display via the GoldDisplay shared component

### 5.2 Header behavior across sub-tabs

The header is always visible regardless of which sub-tab is active — it is the at-a-glance dashboard for "is this domain healthy?"

- Header values refresh on:
  - Monthly resolution events (revenue collected, expenses paid, morale rolled, growth resolved)
  - Player actions in any sub-tab that affect the displayed values (e.g., commissioning a stronghold expansion in the Stronghold sub-tab updates the Stronghold compliance indicator on completion)
  - `EventBus.domain_state_changed` signal (project-designed signal, to be declared in `gdd-ui-shared-services.md` §5.3)

### 5.3 Header empty / pre-domain state

When the active entity does not yet hold a domain, the header shows a compact prompt rather than a status line:

```
+---------------------------------------------------------------------+
| No domain yet  ·  See Overview tab for acquisition guidance         |
+---------------------------------------------------------------------+
```

For a level-9+ entity without a domain, the prompt is more pointed (per the empty-state §22): *"You may now acquire a domain. See Overview for class-tailored guidance."*

For a sub-9 entity, the prompt notes the level threshold but also the pre-9 paths available: *"Followers begin arriving at level 9. You may still acquire and develop a domain via [class-specific path summary]."*

### 5.4 Multi-domain indicator

If the active entity's *realm* contains vassal domains (i.e., they are a higher-tier ruler), a small affordance to the right of Row 1 indicates "Realm: {N} domains" with a click handler that switches to the Realm sub-tab. This keeps the at-a-glance view focused on the personal domain while signaling realm scope.

### 5.5 Chaotic domain visual treatment

For chaotic domains per `ax_domains_of_chaos.xml`, the header uses a subtly distinct visual treatment (Theme variant `header_chaotic_tint`, to be declared) — typically a darker / red-tinted background — so the player can immediately distinguish chaotic-domain rule from lawful/neutral. The classification badge ("Civilized · Chaotic" / "Borderlands · Chaotic" / "Wilderness · Chaotic") uses the chaotic alignment color.

---

## 6. Overview sub-tab

The Overview sub-tab is the default landing page on session-first activation. It consolidates the population, growth, demographics, land value, alignment/religion, and headline-morale concerns into a single scannable view. Per Q4 resolution, the originally-separate Population & Growth content is merged here.

### 6.1 Layout sections (top to bottom)

1. **Domain identity card** — name (editable), classification with sufficiency-to-advance hint, territory composition (list of hexes with their land values and dominant terrain), establishment date, alignment, dominant religion (per `acore_axioms_strongholds_and_domains.xml` §tithes — bladedancer/cleric rulers default to their own religion; otherwise the prevailing local religion)
2. **Demographics summary** — peasant family count broken down by:
   - Per-hex distribution (which hexes hold how many families)
   - Race composition (relevant for chaotic clanholds and for racial-mod growth bonuses per `acore_axioms_strongholds_and_domains.xml` §active_adventuring_growth — elven +2 categories, dwarven +1)
   - Urban families if the domain hosts an urban settlement (per `acore_axioms_strongholds_and_domains.xml` §urban_settlements)
   - Headline-morale band (echoing the header for emphasis)
3. **Growth section** — last-month growth roll history with explicit math breakdown:
   - Random-growth dice (2 × 1d10 per 1000 families with exploding-10 rule per §domain_growth)
   - Investment growth (1d10 per 1000gp per §investments)
   - Active-adventuring growth (per §active_adventuring_growth — band-based bonus + race modifiers; conditional on the ruler having actively adventured at least once in the prior month per the §6.2 heuristic — left stronghold + at least one of wilderness encounter / dungeon-or-lair entry / battle / siege)
   - Net change with a "net families this month" headline
4. **Land Value section** — per-hex 3d3 land value (per §land_value), with surveying status (assessed via Land Surveying proficiency, settled-and-revealed, or unknown). Includes any active land improvements (25,000gp per +1gp value, max +3, max 9 per §land_improvement) and their fragility status (lost gp from pillaging)
5. **Classification advancement section** — for each next-tier threshold per §classification_advancement, show progress (e.g., "Borderlands → Civilized: every hex at 250 fam max + urban settlement with 20% of total + within 48 miles of friendly city or large town. Currently: 4/6 hexes at max, urban yes, distance qualifies. Need: 2 more hexes at max OR contiguous-expansion-blocked condition."). For wilderness → borderlands and borderlands → civilized advancement
6. **Alignment & religion** — current ruler alignment vs. apparent domain alignment (per §alignment_and_religion). If mismatch, surfaces the −1 or −2 base morale penalty. Religion section shows current dominant religion + tithes status, and any in-progress religious conversion per §new_religion (the −4 first-month / −2 thereafter penalties + Dedicated-or-half-population convergence conditions)
7. **Recent significant events** — last 5 events from this domain's log (revenue collected, morale roll outcome, encounter, vassal-favor, calamity). Click to open Encounters & Threats or Treasury & Ledger as appropriate

### 6.2 Editable elements

The Overview sub-tab supports these in-place edits (project-designed UI affordances over RAW state):

- **Domain name** — pencil-icon edit on the identity card; text input with character-limit validation; persists immediately on Enter or focus-blur
- **Land Value reveal** — when a hex's land value is unknown but a Land Surveying proficiency throw is available (i.e., a character with the proficiency is present in the domain), surface a "Survey hex" button per `ax_campaign_play.xml` §survey activity (1 minor strenuous activity per hex, target 18+ base modifying with cumulative +4 per prior successful search — but Survey requires Land Surveying; the ACKS RAW differentiation is preserved)
- **Tax / liturgy / tithe rate adjustment** — per `ax_campaign_play.xml` §issue_decree, changing tax or liturgy rate is a minor or trivial activity for the ruler in their domain. The Overview sub-tab surfaces the current rates (default 2gp / 1gp / 1gp per family) with +/− steppers to adjust. Each adjustment is logged immediately and dispatched as an `issue_decree` activity per `gdd-realtime-scheduler.md` §4.8 (Singular Minor frequency, carrying its time cost against the ruler's daily ~8-hour active-work budget); impact appears next monthly resolution per the morale-event modifiers in §monthly_event_modifiers
- **Active adventuring detection** (project-designed; automatic, no manual toggle per O-D1 resolution) — for `acore_axioms_strongholds_and_domains.xml` §active_adventuring_growth purposes (the population-growth bonus per the band table) AND for `ax_campaign_play.xml` §administer_domain "+5% domain XP" purposes, the ruler is considered to have "actively adventured" in a given month if BOTH conditions are met:
  1. The ruler physically left their stronghold (or any domain stronghold they hold) during the month, AND
  2. At least one of the following adventuring events occurred to the ruler during the month:
     - A wilderness encounter (per `acore_adventures_and_encounters.xml` wandering monster rules)
     - The ruler entered a dungeon or lair (any subterranean encounter location)
     - The ruler fought in a battle (any combat encounter — not just mass-combat per `daw_axioms_pitching_battle.xml`)
     - The ruler participated in a siege (per `daw_sieges.xml` — either as besieger or defender)
  
  The Overview sub-tab shows "Active this month: yes / no" status with a tooltip listing which conditions have been met (e.g., "Left stronghold ✓ · Wilderness encounter ✓ · Dungeon visit ✓"). The detection is event-driven via `EventBus` subscriptions (left_stronghold, wilderness_encounter_resolved, dungeon_entered, lair_entered, combat_started, siege_started); no manual override per O-D1.

### 6.3 Pre-9th-level Overview content

For a level-1-through-8 entity who owns a domain, the Overview sub-tab shows the same content with the following adjustments:

- The "Followers expected" data row shows "Followers begin arriving at level 9 (currently level X)"
- The Demographics summary's race composition is determined by the existing-domain population (per `acore_axioms_strongholds_and_domains.xml` §before_ninth_level: *"If such a character acquires an existing domain, the current number of families remains. If such a character acquires a new domain, it begins with no families."*) — so a sub-9 ruler who built a stronghold from scratch shows zero families until they invest gp to attract or hire mercenaries, and a sub-9 ruler who acquired an existing domain shows the inherited population
- Active-adventuring growth still applies (RAW does not gate that on level)
- Investment growth still applies (1d10 per 1000gp per §investments)
- A persistent banner near the top: *"Followers and peasants do not arrive automatically until you reach level 9. You may still build, invest, hire mercenaries, and grow your domain."*

### 6.4 Chaotic-domain Overview content

For a chaotic domain per `ax_domains_of_chaos.xml`:

- Demographics race composition is beastman per §followers (the ruler's beastman followers + the clanhold-derived population)
- Population limits show 125 fam/6-mi-hex (the chaotic / wilderness limit)
- Urban settlement section (if any) shows the chaotic-specific limits — max 250 urban fam, max class VI without investment-driven advancement (with chaotic-specific advancement costs: 2,000gp per 1d10 fam; 50,000gp for class V; urban revenue capped at 7gp/fam)
- Investment-value displays show the halved value per `ax_domains_of_chaos.xml` §exceptions_from_clanholds
- Garrison cost displayed minimum is +2gp over the normal classification minimum

---

## 7. Stronghold sub-tab

The Stronghold sub-tab is a status-and-summary view over the active entity's stronghold(s). Construction details, archetype design, and the commission pipeline are owned by `gdd-stronghold-construction.md`; this sub-tab presents the *outputs* and offers cross-activation into that surface.

### 7.1 Layout sections

1. **Active stronghold(s)** — list of completed strongholds belonging to this domain (typically one, but a domain may host multiple strongholds whose total value combines per `acore_axioms_strongholds_and_domains.xml` §minimum_stronghold_value: *"If a domain has multiple strongholds, add their total value together."*). Each stronghold shows:
   - Name (player-assigned; defaults to "[Class Structure Type] of [Domain Name]" e.g., "Castle of Eastmarch")
   - Structure type per the active entity's class (castle / sanctum / fortified church / hideout / fastness / underground vault / cloister / temple / hall / border fort / dark fortress / chieftain's hall / cloister / medicine lodge / coterie / coven / guildhouse — per the matrix in §12.1)
   - Total gp value (per `gdd-stronghold-construction.md` §2 catalog)
   - Total SHP per `daw_sieges.xml` §structural_hit_points
   - Unit capacity per `daw_sieges.xml` §unit_capacity
   - Current condition (full SHP / damaged / under reduction / breached)
   - Maintenance status (current month maintenance paid / overdue gp)
   - Cross-activation: "View construction" → `gdd-stronghold-construction.md` battle-map / detail surface (when implemented)
2. **Sufficiency vs. minimum** — calculation per `acore_axioms_strongholds_and_domains.xml` §minimum_stronghold_value:
   - Required minimum (Civ 15,000gp / Bord 22,500gp / Wild 32,000gp per 6-mile hex; ×16 for 24-mile, ÷16 for 1.5-mile)
   - Current total stronghold value
   - Sufficiency percentage and the corresponding base morale penalty: ≥100% = no penalty; ≥50% = −1; ≥25% = −2; <25% = −3
   - Noncontiguous-domain check per §noncontiguous_domains: if the domain is noncontiguous, the stronghold(s) must secure all noncontiguous hexes AND the intervening hexes; a "Coverage warning" surfaces if not
3. **Pending construction projects** — list of in-progress construction projects on this domain per `gdd-stronghold-construction.md` §6:
   - Project name and structure type
   - Cost / progress (gp invested vs. gp total)
   - Current monthly construction rate (per assigned workers)
   - Estimated completion date
   - Assigned supervisor (per `gdd-stronghold-construction.md` §5.2 — engineer or siege engineer required for large projects)
   - Magic-assistance status if any per `gdd-stronghold-construction.md` §5.5
   - Oversee/supervise activity-link buttons (per `ax_campaign_play.xml` §oversee_construction and §supervise_construction): "Oversee this project" (active when ruler is at the construction site, +5% rate; +10% if also supervising; greyed otherwise with travel shortcut), "Supervise this project" (requires Engineering / Siege Engineering proficiency)
4. **Maintenance & repair** — per `acore_axioms_strongholds_and_domains.xml` §maintenance: 1gp per peasant family monthly. Each gp of unpaid maintenance reduces stronghold value by 1gp. Section displays cumulative deferred maintenance gp and the resulting value-loss; surface a "Pay deferred maintenance" button when deferred-gp ≥ 0
5. **Commission new construction** — cross-activation button to `gdd-stronghold-construction.md` §5 commission pipeline. Pre-fills the active entity's class for archetype-selection defaulting (e.g., a Mage opens to the Sanctum archetype)
6. **Claim existing structure** — per `acore_axioms_strongholds_and_domains.xml` §establishing: *"If an existing suitable structure is present in the domain, it may be claimed as the stronghold."* Cross-activation to `gdd-stronghold-construction.md` §8.4 (Dungeon-Stronghold Bridge for claiming existing dungeon structures) or to a generic structure-claim flow for ruined/abandoned strongholds discovered in the domain's territory

### 7.1.1 Non-conforming strongholds (per O-D10)

A "non-conforming stronghold" is one whose structure type does not match the active entity's class — e.g., a Mage who has inherited a Fighter's castle instead of building a Sanctum, or a Cleric who has conquered a hideout instead of building a Fortified Church.

Per O-D10 resolution:

- **Building a non-conforming stronghold is NOT permitted.** The Stronghold sub-tab's "Commission new construction" button restricts the available archetypes to the active entity's class-appropriate type only. A Mage cannot build a fortress; a Fighter cannot build a sanctum; etc.
- **Inheriting or conquering a non-conforming stronghold IS permitted.** Per `acore_axioms_strongholds_and_domains.xml` §establishing: *"If an existing suitable structure is present in the domain, it may be claimed as the stronghold."* The Stronghold sub-tab supports claiming any existing structure regardless of its type vs. the active entity's class
- **No followers attracted by a non-conforming stronghold.** Per RAW the per-class follower attraction (per `acore_core_classes.xml` §<class>.stronghold_and_followers) is tied to the class-specific structure type. A non-conforming stronghold satisfies the minimum-stronghold-value gp threshold (i.e., satisfies the morale-penalty mitigation per §insufficient_stronghold) but does NOT trigger the class's `<followers>` table arrival
- The Stronghold sub-tab clearly flags non-conforming strongholds with a "Non-conforming" badge and a tooltip explaining the no-followers consequence

**Cross-doc obligation:** `gdd-stronghold-construction.md` will need updates to clarify (a) how stronghold type is classified during build (currently the construction GDD doesn't carry the structure-type-vs-class-binding metadata explicitly), and (b) whether converting an existing stronghold from one type to another is supported (e.g., a Fighter's castle being converted into a Mage's sanctum — likely requires substantial rebuild). These are **out of scope for this Domain tab GDD** but flagged for cross-GDD coordination during build.

### 7.2 Class-specific stronghold notes

The Stronghold sub-tab content is structurally identical across classes — every class may commission *some* structure at any level — but the **type** of structure varies per the matrix in §12.1. Level 9 does not gate the ability to build; it gates whether that structure attracts the class's named follower type (per `acore_core_classes.xml` §<class>.stronghold_and_followers) — see §6.4/§19.2. The Stronghold sub-tab labels and visuals adapt: a Mage's tab shows a sanctum / tower icon; a Cleric's a fortified church; a Thief's a hideout; etc.

For **Explorer** specifically: the stronghold is a border fort, and per `acore_axioms_strongholds_and_domains.xml` §classification *"Explorers may only build strongholds in borderlands or wilderness domains."* The "Commission new construction" button for an Explorer gates the structure-build flow to borderlands/wilderness territory; civilized territory shows a tooltip explaining the class restriction.

For **Dwarven** classes (Vaultguard / Craftpriest / Delver / Fury): the stronghold is an underground vault. Per `acore_axioms_strongholds_and_domains.xml` §classification *"dwarven vaults may only be built in wilderness areas or civilized/borderlands areas of their own race."* The build flow gates accordingly.

For **Elven** classes (Spellsword / Courtier / Ranger): the stronghold is a fastness which "must blend seamlessly with nature" per `acore_demihuman_classes.xml`. Same wilderness-or-own-race restriction. The fastness archetype's grid placement rules in `gdd-stronghold-construction.md` §3 should reflect this design intent (project-designed UI for archetype constraints — cross-doc concern flagged via the `gdd-stronghold-construction.md` §13 open questions Q5 / Q6 added 2026-04-30).

For **Mage** specifically: per `acore_core_classes.xml` §Mage `<acquisition_rules>`, *"If the mage builds a dungeon beneath or near the tower, monsters will start to arrive to dwell within, followed shortly by adventurers seeking to fight them."* The Stronghold sub-tab includes a Mage-specific "Build dungeon under tower" option that opens the dungeon-construction flow (per `gdd-stronghold-construction.md` §2.1 dungeon corridor structures, lines 36 of the catalog). This is a unique feature of the mage class.

For **Cleric / Bladedancer / Priestess / Shaman**: per `acore_core_classes.xml` §Cleric `<acquisition_rules>`, *"If currently in favor with the deity, may buy or build the fortified church at half the normal price due to divine intervention."* The Stronghold sub-tab surfaces a "Divine favor status" indicator and applies the half-price discount when applicable.

### 7.3 Multi-stronghold display

When a domain has multiple strongholds (per `acore_axioms_strongholds_and_domains.xml` §minimum_stronghold_value the values combine), the Stronghold sub-tab renders each as a row in a list, with the total displayed in the Sufficiency calculation. A "+ Add stronghold" cross-activation opens the commission pipeline for an additional stronghold within the same domain.

### 7.4 Empty stronghold state (no stronghold yet)

For a level-9+ entity who has territory but no stronghold, the Stronghold sub-tab shows an empty-state with strong CTA: *"You hold {N} hexes of {classification} territory but have no stronghold. Without sufficient stronghold value your peasants generate no income and your domain does not grow."* Followed by class-specific options:
- Commission new {structure-type}
- Claim an existing structure if one has been discovered in the territory

For a sub-9 entity, the same empty-state appears with the additional banner regarding pre-9 status.

For a level-9+ entity who holds NO territory at all, the Stronghold sub-tab is essentially the empty-state of the whole tab (covered by §22 Empty-state).

---

## 8. Garrison sub-tab

The Garrison sub-tab is a per-domain view of the troop units assigned to defend or campaign from this domain. It is a *summary* view over the Troops tab data — the Troops tab owns unit lifecycle; the Garrison sub-tab owns the per-domain assignment perspective.

### 8.1 Layout sections

1. **Garrison composition** — list of troop units with `assignment.location_domain_id == this_domain.id` (per the project-designed troop assignment data model — to be confirmed in `gdd-troops-tab.md`):
   - Unit name / type / source flag (mercenary / conscript / militia / follower / slave-soldier / vassal-troop / tribal-warrior per `daw_armies_recruitment.xml` §army_sources and `ax_domains_of_chaos.xml` §military)
   - Headcount (current / nominal)
   - Battle Rating per `daw_campaigns_troop_tables_summary.xml` (BR is the canonical unit-strength metric for siege and domain-encounter resolution)
   - Monthly cost (per troop type and race per the troop tables summary)
   - Morale band
   - Cross-activation: click → switches to Troops tab Roster filtered to this unit
2. **Garrison cost compliance** — per `acore_axioms_strongholds_and_domains.xml` §garrison:
   - Required monthly minimum: 2gp/family (Civilized), 3gp/family (Borderlands), 4gp/family (Wilderness; less reduces base morale per §classification_modifiers)
   - For chaotic domains per `ax_domains_of_chaos.xml`: +2gp/family above classification minimum
   - Current monthly garrison spend on this domain (sum of all assigned units' monthly costs)
   - Sufficiency indicator and any base-morale penalty
   - Special-counting rules surfaced inline:
     - **Faithful followers of clerics and bladedancers count by gp value** even if unpaid per §garrison
     - **Trained and equipped militia count by gp value** even when not called up per §garrison
     - **Troops provided by a lord as a favor count toward garrison cost** even though the ruler is not paying them per §garrison
     - **Scutage paid to a lord counts toward garrison expense** per §garrison (when the active entity is a vassal paying scutage instead of mustering)
3. **Additional troops for morale bonus** — per `acore_axioms_strongholds_and_domains.xml` §additional_troops:
   - For Borderlands: +1 base morale if 1gp/family of additional troops are garrisoned beyond the minimum
   - For Wilderness: +1 base morale at 1gp/family additional, +2 at 2gp/family
   - Display current additional gp/family and resulting bonus
4. **Repression** — per `acore_axioms_strongholds_and_domains.xml` §repression:
   - 1gp/family additional troops repressing → +1 morale roll bonus (current morale capped at 0 while repressed)
   - 2gp/family additional → +2
   - +1 per additional full gp/family above
   - Display current repression spend if any; toggle to enable / disable repression mode for the next monthly resolution
   - Note prominently: *"Militia cannot be used to repress the peasantry."* per RAW
5. **Levy controls** (per the active entity's class and applicable domain type):
   - **Conscript troops** activity per `ax_campaign_play.xml` §conscript_troops: 1 conscript per 10 peasant families maximum, 1-3 weeks arrival schedule. Surfaced as an action button (notebook-side; greyed unless ruler is in their domain)
   - **Levy militia** activity per `ax_campaign_play.xml` §levy_militia: 2 peasants per 10 peasant families maximum, 1-3 weeks. Same gating
   - **Levy tribal warriors** for chaotic domains and beastman clanholds per `ax_domains_of_chaos.xml` §tribal_warriors: 1 tribal warrior per tribal family without morale penalty; mix per `<tribal_warrior_troop_type_per_120_warriors>` table
   - **Suppression note** — when current morale is at Rebellious / Defiant / Turbulent (≤−2), the levy controls show: *"Conscripts and militia cannot be levied. Domain morale is {Rebellious/Defiant/Turbulent}."* per §effects_of_morale
6. **Hire mercenaries** — `ax_campaign_play.xml` §hire_mercenaries activity. Cross-activation to the Settlement Panel's HiringPanel (which lives in `gdd-settlement-exploration-ui.md`) per the established cross-surface pattern. Dispatched as `hire_mercenaries` via the activity time-cost executor per `gdd-realtime-scheduler.md` §4.8; vagaries-of-recruitment roll triggered per RAW on session completion
7. **Mercenary officer assignments** — per `daw_campaigns_troop_tables_summary.xml`, Lieutenants / Captains / Colonels / Generals are separately-hired specialists. The Garrison sub-tab surfaces officer-to-unit assignments inline so the player can see which units have officers and their rank. Cross-activation to the Troops tab handles officer-management details

### 8.2 Troop training (proficiency-gated, per Q14 [RESOLVED 2026-05-11])

Per Q14 [RESOLVED 2026-05-11], troop training is **proficiency-gated**, not class-gated. Manual of Arms (with combinable Riding and Weapon Focus enabling different troop types) is the canonical mechanism. Any class can take the Manual of Arms proficiency — Fighter is the most common but Clerics, Bladedancers, and other non-fighter-progression characters may have it too. An equivalent class power also satisfies the gate (see §8.2.1).

A **"Training" sub-section** appears in the Garrison sub-tab body when the active entity has Manual of Arms proficiency (rank 1+) or an equivalent class power. The sub-section contains:

- **Training queue** — list of in-progress / pending troop-training projects. Each entry shows: unit name, troop type being trained (light infantry / heavy infantry / light cavalry / heavy cavalry / crossbowmen / bowmen / longbowmen / horse archers / cataphract cavalry), training-time-remaining, eligibility-check result (proficiency rank + companion proficiencies vs. troop-type requirements per Manual of Arms RAW).
- **Training activity launchers** (each gated on proficiency/eligibility):
  - **Train troops** (`train_troops` activity per `ax_campaign_play.xml`) — major ongoing. Eligibility: Manual of Arms proficiency rank 1+ (light infantry; 1 month / 30gp per month earnings) or rank 2 (heavy infantry; 1 month / 60gp per month). Combinable: rank 1 + Riding = light cavalry (3 months); rank 1 + Weapon Focus (bows & crossbows) = crossbowmen (1 month) / bowmen (2 months) / longbowmen (3 months); rank 1 + Riding + Weapon Focus = horse archers (6 months); rank 2 + Riding = heavy cavalry (6 months); rank 2 + Riding + Weapon Focus = cataphract cavalry (12 months). Maximum 60 soldiers per training period.
  - **Oversee troop training** (`oversee_troop_training` activity) — minor ongoing. The activity's RAW eligibility text reads *"Fighter or other character using fighter attack progression, level 5+, who rules a domain"* but per Q14 the principle is broader: the activity surfaces here for the ruler of the domain (the noble-overseer angle, not the trainer). Provides +1 permanent morale bonus to overseen troops on completion.
  - **Inspect troops** (`inspect_troops` activity) — minor singular. Available to the ruler of the domain. Provides +1 morale on the next combat roll.
- **Eligibility readouts** — per-troop-type table showing which troop types the active entity is currently authorized to train (based on their proficiency rank + companion proficiencies + any equivalent class powers).

**[FOLLOW-UP — Q14a PENDING]** Which specific `class_powers` from the project's class JSON files count as "Manual of Arms equivalent"? Candidates surveyed:
- `battlefield_leadership` (Fighter) — possibly equivalent? Or a different ability entirely?
- `fighter_damage_bonus` (Fighter / Bladedancer / Paladin / Anti-Paladin / Barbarian / etc.) — does NOT seem to grant training capability per RAW; it's a damage modifier.

Pending Jedidiah's Q14a ruling on the specific class-power allowlist. Implementation default until resolved: ONLY Manual of Arms proficiency rank 1+ grants training eligibility; no class powers granting it automatically. Fighter and similar classes must take Manual of Arms via the proficiency progression to train troops, just like any other class.

### 8.2.1 Class-specific roster annotations

- **Cleric / Bladedancer / Priestess / Shaman**: faithful-follower count is highlighted in the composition list with a special "Faithful (no wages)" badge. The +4 morale and complete loyalty per `acore_core_classes.xml` §Cleric `<loyalty_or_morale_rules>` is surfaced inline.
- **Dwarven classes**: composition list flags "Dwarven soldiers" status — per `acore_demihuman_classes.xml` §Vaultguard `<loyalty_or_morale_rules>`: *"The character is expected to employ only soldiers of dwarven descent. Members of other races may be hired for non-soldier tasks."* Non-dwarven soldier units show a warning indicator; non-dwarven non-soldier hirelings are fine.

### 8.3 Multi-domain garrison context

When the active entity rules multiple domains (a personal domain + vassal domains via henchmen), the Garrison sub-tab shows **only the active entity's personal domain garrison.** Vassal-domain garrisons are managed via switching to the vassal henchman as active entity. The Realm sub-tab provides realm-wide garrison aggregates.

---

## 9. Realm sub-tab

The Realm sub-tab is the highest-tier ruler view: vassal management, tribute flows, favors / duties, realm aggregates, title display.

### 9.1 Layout sections

1. **Title and realm summary card** — per `acore_axioms_strongholds_and_domains.xml` §titles_of_nobility:
   - Current title (Baron / Marquis / Count / Duke / Prince / King / Emperor) computed from personal-domain families, domains-ruled count, and overall-realm-families count
   - Title in vernacular per the realm's setting per the table (e.g., Auran Empire = Castellan / Tribune / Legate / Palatine / Prefect / Exarch / Tarkaun)
   - Personal domain family count
   - Domains-ruled count
   - Overall realm family count
   - Tribute efficiency factor (per `acore_axioms_strongholds_and_domains.xml` §tribute_inefficiency table — at 16+ direct vassals, efficiency drops; max efficiency at 8 or fewer direct vassals)
2. **Vassal list** — table with one row per vassal domain in this entity's realm:
   - Vassal name (henchman name + race + class + level if henchman; "[Non-henchman vassal name]" otherwise)
   - Vassal type — Henchman vs. Non-henchman (per §non_henchman_vassals: non-henchman vassals have base loyalty −2; −4 if outside trade range)
   - Vassal's domain name
   - Vassal's domain classification + size + family count
   - Vassal's current morale band
   - Tribute paid (vassal → this ruler) per §tribute
   - Favors active (count, with hover tooltip showing list)
   - Duties active (count, with hover tooltip showing list)
   - Loyalty band (last roll outcome — analogous to the Henchmen tab Loyalty display)
   - Cross-activation: click → switches active entity to vassal henchman, Domain tab on their domain
3. **Tribute flows** — per `acore_axioms_strongholds_and_domains.xml` §tribute:
   - Total monthly tribute from vassals (raw, before efficiency penalty)
   - Tribute efficiency factor (from §tribute_inefficiency)
   - Effective tribute received this month
   - Outgoing tribute to this entity's lord, if any (the entity is a vassal)
   - Tribute by realm-families lookup display per §tribute_by_realm_families table or §precise_optional_formula `18 × realm_families^0.6`
4. **Favors and duties tracker** — per `acore_axioms_strongholds_and_domains.xml` §favors_and_duties:
   - Active favors granted to vassals (Charter of Monopoly / Gift / Office / Troops / Grant of Land per the d20 table)
   - Active duties demanded of vassals (Construction / Scutage / Call to Council / Call to Arms / Loan)
   - Favor / duty balance per vassal: each vassal can safely be asked one ongoing duty + one additional duty per ongoing favor + one-time-favor offsets within the month they're given. Excess triggers Henchman Loyalty checks per §favors_and_duties
   - Monthly favors-and-duties d20 roll (when the active entity is a vassal — rolled at start-of-month per `ax_campaign_play.xml` §random_events / §favors_and_duties subphase)
   - Display the muster delay table per §muster_delay (Emperor/King = season; Prince/Duke = month; Count/Marquis/Baron = week) for this entity's title
5. **Add vassal** — controls for assigning a domain to a henchman as a vassal:
   - "Assign domain to henchman" button (project-designed UI affordance) — opens a flow that lets the player select an existing humanoid henchman + an existing domain owned by this entity. Per `acore_axioms_strongholds_and_domains.xml` §realms_and_vassals: *"Vassals are usually henchmen, but may themselves hold vassal realms..."*
   - When the player has insufficient henchmen, the section surfaces the rule from §realms_and_vassals: *"If henchmen are insufficient, multiple domains may be assigned to a trusted henchman, who must then create sub-vassal structure below them."*

### 9.2 Realm-wide aggregates

The Realm sub-tab includes a "Realm Aggregates" card (collapsible, default collapsed) that sums across the personal domain and all vassal domains:
- Total realm population (peasant + urban families)
- Total realm income (sum of personal-domain income + tribute received, less outgoing tribute)
- Total realm garrison strength (sum of all units across all domain garrisons)
- Realm-wide morale roll-up: count of domains by morale band

This serves as the "ruler dashboard" view for high-tier players running large realms.

### 9.3 Empty Realm sub-tab

When the active entity has no vassals and is not themselves a vassal, the Realm sub-tab shows a minimal empty-state: *"No vassals yet. As your domain grows you may delegate territory to henchmen as vassal rulers."* + a "Learn about vassalage" link surfacing the §realms_and_vassals rule summary in a tooltip / modal (project-designed in-context help).

### 9.4 Vassal-with-no-heir default: reverts-to-overlord (Phase 11C, v1)

When a vassal henchman dies and no heir is designated before the succession grace period (1 game-month) lapses, the vassal's domain **reverts to the overlord under direct rule** rather than passing to abandonment. Mechanically:

- The vassal_assignment row terminates (`status='departed'`).
- `domains.liege_domain_id` is cleared (the domain is no longer a vassal).
- `domains.owner_character_id` reassigns to the overlord PC.
- `lifecycle_state` returns to `active`; the overlord runs the domain directly from the next monthly tick.

A `succession_lapsed` departure-log entry records the overlord transfer. The overlord may subsequently delegate the domain to a new vassal via the standard Realm sub-tab "Assign domain to henchman" flow.

**Why this default and not abandonment:** abandonment of a vassal's domain on grace lapse would force the overlord to swallow the loss of a productive realm-tier asset for an in-game admin oversight. Reverting to overlord direct rule preserves the realm's economic state while still imposing a cost (overlord now juggles an extra direct-rule domain, with its own per-domain tribute-efficiency consequences per `acore_axioms_strongholds_and_domains.xml` §tribute_inefficiency).

**Placeholder for ACKS Dynasties:** this default is the v1 fallback. The long-term intent is the ACKS Dynasties bloodline-heir succession model — named bloodline relatives of the deceased ruler become the default heir-list, with the player choosing among them rather than from the open `eligible_heirs_for(domain_id)` list. The Phase 11C state machine + `designated_heir_*` columns are already shaped to accept a future bloodline-heir resolver; the reverts-to-overlord fallback should be preserved as the "no-bloodline-heir-available" terminal case. See `memory/project_dynasties_succession.md`.

---

## 10. Treasury & Ledger sub-tab

The Treasury & Ledger sub-tab provides month-by-month financial detail for the domain, plus an unpaid-expenses warning system and configurable monthly auto-pay policies.

### 10.1 Treasury data model (project-designed)

The Treasury & Ledger sub-tab presents a domain-scoped ledger that is *separate* from the active entity's personal coin wallet (per `gdd-character-tab.md` §4.8 — money is an item with a carrier; a character's personal wallet is the coin they carry). The domain has its own treasury, conceptually held in the stronghold's vaults. Project-designed data model:

```
domain_treasury {
  domain_id: String
  current_balance_gp: int           # accumulated gp held by the domain
  monthly_revenue_pending_gp: int   # earned but not yet collected this month
  monthly_expenses_pending_gp: int  # owed but not yet paid this month
  deferred_maintenance_gp: int      # accumulated unpaid maintenance per §maintenance
  auto_pay_policies: Dictionary
  ledger_entries: Array[LedgerEntry]
}

LedgerEntry {
  timestamp: int (in-game time tick)
  type: "revenue" | "expense" | "transfer_in" | "transfer_out" | "investment" | "construction"
  category: "land" | "service" | "tax" | "tribute_in" | "tribute_out" | "garrison" | "liturgy" | "maintenance" | "tithe" | "investment_agriculture" | "investment_urban" | "construction_progress" | "stronghold_repair" | "manual_transfer" | ...
  amount_gp: int (positive for inflow, negative for outflow)
  description: String
  related_entity_id: String? (e.g., vassal_id for tribute, mercenary_unit_id for wages)
}
```

The Treasury & Ledger sub-tab presents this data; the engine writes to it via monthly resolution and player-initiated activities.

### 10.2 Layout sections

1. **Headline numbers card** —
   - Current treasury balance (gp held by the domain)
   - This month's net income projection (revenue pending − expenses pending)
   - Last month's actual net income (for comparison)
   - Twelve-month rolling net income trend (small inline chart — project-designed visual)
   - Unpaid expenses alert if any
2. **Revenue breakdown** (this-month-pending and prior-month-actual columns) —
   - Land revenue per §domain_revenue (3-9gp per family per month; varies by hex)
   - Service revenue (4gp per family)
   - Tax revenue (2gp per family base; modified by current tax rate set via §issue_decree)
   - Tribute received from vassals (per §tribute, with efficiency factor applied)
   - Special tax revenue if Tax Demanded duty was imposed last month per `ax_campaign_play.xml` §revenue_collection §special_taxes
   - Loan revenue if Loan Demanded duty was imposed last month
   - Investment revenue (mercantile ventures by venturer with monopoly per `ax_venturer_class.xml` §monopoly; other investment yields)
   - Hijink revenue per `ax_campaign_play.xml` §hijink_revenue (for thief / assassin / nightblade rulers)
3. **Expense breakdown** (this-month-pending and prior-month-actual columns) —
   - Garrison cost (per §garrison; current spend may exceed minimum)
   - Liturgies (1gp per family per §liturgies; rate adjustable via §issue_decree)
   - Maintenance (1gp per family per §maintenance; deferred-maintenance-tracked)
   - Tithes (1gp per family per §tithes)
   - Tribute paid to lord if applicable
   - Living expenses (per `ax_campaign_play.xml` §living_expenses end-of-month subphase)
   - Hireling wages including henchman / mercenary / specialist wages per `ax_campaign_play.xml` §hireling_wages
   - Settlement expenses if domain has urban settlement
   - Congregant expenses for divine spellcaster rulers (1gp per congregant per `ax_campaign_play.xml` §congregants)
   - Construction project monthly investment (per active stronghold / building / dungeon construction)
4. **Auto-pay policies** (project-designed) — toggles for the player to pre-authorize monthly expense payment from treasury:
   - Pay garrison cost from treasury automatically: yes / no
   - Pay maintenance from treasury automatically: yes / no
   - Pay tithes from treasury automatically: yes / no
   - Pay tribute to lord from treasury automatically: yes / no
   - Pay henchman / mercenary wages from treasury automatically: yes / no
   - Pay congregant expenses from treasury automatically: yes / no (cleric/bladedancer rulers only)
   - When unchecked, the monthly resolution surfaces a prompt to the player to authorize payment manually before applying the morale-roll modifiers
   - When checked but treasury is insufficient, the engine pays what it can and logs the remainder as "unpaid" — the morale-event modifiers per §monthly_event_modifiers apply (e.g., "Garrison expenditure below 2gp/family this month: −1 per gp below")
5. **Manual transfers** — buttons to:
   - Transfer gp from active entity's personal wallet → domain treasury
   - Transfer gp from domain treasury → active entity's personal wallet
   - **Per O-D2 resolution:** transfers are activity-free **but require the active entity to be physically at one of the domain's strongholds** (where the treasury is held). Greyed elsewhere with the standard wrong-location tooltip + travel shortcut. Rationale: the treasury is held in the stronghold's vaults; transfers are physical coin movement, not abstract banking
6. **Ledger** — virtualized list of `LedgerEntry` records, default sorted reverse-chronological. Filterable by type, category, date range. Search by description text. Export per the established export pattern in `gdd-unified-log-panel.md` §10 (markdown / JSON / TXT)

### 10.3 Treasury vs. personal wallet boundary

This is an important design decision: the domain treasury is conceptually distinct from the ruler's personal coin wallet. Revenue collected goes to the domain treasury, not the ruler's pocket. Expenses are paid from the treasury. The ruler may transfer between personal wallet and treasury manually as needed.

Per ACKS RAW the boundary is implicit — the rules speak of "domain income" and "ruler's wealth" without explicit treasury mechanic — but the project-designed treasury model makes the boundary explicit so:
- The ruler doesn't accidentally bankrupt themselves trying to pay garrison from personal pocket
- The treasury is part of the domain (raidable in pillaging per §pillage)
- Multi-PC parties have unambiguous gp ownership: each PC's domain treasury is theirs alone; only personal-wallet gp aggregates into the Party Wallet per `gdd-character-tab.md` §4.8

This is **Arbiter-specific design** — flagged here so future readers understand it's a project decision, not RAW.

### 10.4 Unpaid expenses alert

When any expense category has unpaid gp accumulated (deferred maintenance, missed tithe, missed tribute, missed garrison wages), the headline-numbers card displays a warning indicator with the specific consequences:
- Deferred maintenance: each gp unpaid reduces stronghold value by 1gp per §maintenance
- Unpaid tithes: −1 morale roll modifier per §tithes per `<row event="Tithes not paid this month" adjustment="-1" />`
- Garrison spend below minimum: −1 morale roll modifier per gp below per §monthly_event_modifiers
- Hireling wages unpaid: per `gdd-henchmen-tab.md` and `gdd-troops-tab.md` Calamity rules

---

## 11. Decrees & Remote Orders sub-tab

> **Revision (2026-05-06):** This sub-tab replaces the prior "Activities" sub-tab. The earlier design centralized all domain-and-domain-adjacent activities behind a notebook picker with explicit slot-quota tracking (1 major + 2 minor or 8 minor / day enforced as a UI counter). That design conflicted with the real-time-with-pause architecture established in `gdd-realtime-scheduler.md` and made the game feel like spreadsheet menu-picking. The replacement model is described in `gdd-realtime-scheduler.md` §4.8 "Activity Time Costs and Frequency Semantics": activities are launched from the location of execution (settlements, strongholds, dungeons, wilderness hexes), not from a centralized picker. Tick-tolerance / absence / abandon-and-resume mechanics apply ONLY to Ongoing-frequency activities per §15.1; Singular and Restricted activities are atomic and must be restarted if interrupted. For per-character status visibility into running ongoing activities, see `gdd-character-tab.md` "Active Projects" sub-tab.

This sub-tab surfaces the **small set** of domain activities a ruler can initiate without being physically present at the affected location, on the RAW-supported fiction that the ruler's seneschal, steward, marshal, or chancellor carries out written orders while the ruler is adventuring. All other activities are launched from the location-specific UI surfaces per the per-location activity-launch pattern in `gdd-realtime-scheduler.md` §4.8.4.

### 11.1 Activities surfaced here

Each entry below is RAW-justified as performable without the ruler being at the target location. The list is intentionally short — most domain activities require physical presence (oversee construction at the construction site; train troops at the stronghold; consecrate altar at the altar) and live in their location surfaces, not here.

- **Administer domain** (major ongoing per `ax_campaign_play.xml` §administer_domain). Project interpretation per Jedidiah (2026-05-06): the +1 morale modifier in `acore_axioms_strongholds_and_domains.xml` §administration L499, L526-529 abstracts the work of a seneschal carrying out the ruler's standing orders; therefore administer_domain is RAW-legal as a remote ongoing activity. The ruler need not be physically in the domain on a given day for the activity to bank a tick, provided the ruler has dispatched current orders. Time per day per RAW: ½ × [(6-mile hexes) + (vassals reporting) + (6 − market class of largest urban settlement in personal domain)] days banked toward the month's modifier. Status card displays the formula breakdown and current month's progress.
- **Issue decree** (minor or trivial singular per `ax_campaign_play.xml` §issue_decree). A written order dispatched to the seneschal — does not require physical presence. Sub-flow options:
  - Change tax rate (current rate displayed; +/− stepper; per-month effect on revenue + morale modifier per `acore_axioms_strongholds_and_domains.xml` §monthly_event_modifiers L494-495)
  - Change liturgy rate (default 1gp; +/− stepper; per-month morale roll modifier per §monthly_event_modifiers L492-493)
  - Change tithe rate / declare tithe paid or unpaid (per §tithes L243-249 and §monthly_event_modifiers L496)
  - Grant a favor to a vassal (cross-references §6 Realm sub-tab Favors-and-Duties tracker)
  - Demand a duty of a vassal (same; immediate Henchman Loyalty roll if vassal already has unsafe duties)
  - Free a perpetrator caught committing a crime (project-designed UI hook to the Crime & Punishment system in §12.5 Syndicate; relevant when the ruler chooses to interfere)
  - Order construction of a new stronghold (cross-activate to `gdd-stronghold-construction.md` commission flow; the ruler does not need to be at the construction site to issue the commission, only to oversee or supervise it once underway — those are separate activities at the stronghold UI)
  - Order agricultural or urban investment (gp input + investment-type selector; flows into next-month revenue + 1d10/1000gp population growth per §investments L132-135)
  - Set repression policy (assign N gp/family of additional troops to repression per `acore_axioms_strongholds_and_domains.xml` §repression L510-516; militia troops greyed as ineligible; warning that current morale cannot exceed 0 while active)
- **Manage henchmen** (trivial ongoing per `ax_campaign_play.xml` §manage_henchmen). Per RAW the canonical remote-capable activity — explicitly allowed "whenever the henchman is accessible physically or magically." Card surfaces the active entity's henchmen and their current assignments, with reassignment controls; cross-references the Henchmen tab for henchman-level details. Per `gdd-domain-tab.md` §15.1.3, manage_henchmen has no required location and never accumulates absence.
- **Conscript troops** (minor ongoing; 1-3 weeks per `ax_campaign_play.xml` §conscript_troops). Order issued to the seneschal; recruitment runs in the domain regardless of ruler location. Max 1 per 10 peasant families. Card displays current capacity, conscription progress, and vagaries-of-recruitment status from the monthly random-events phase. Greyed when domain morale is Turbulent / Defiant / Rebellious per `acore_axioms_strongholds_and_domains.xml` §effects_of_morale L555-577.
- **Levy militia** (minor ongoing; 1-3 weeks per §levy_militia). Order issued to the seneschal; same remote-execution fiction as Conscript. Max 2 per 10 peasant families. Same status display. Same morale-band restrictions.
- **Solicit mercenaries** (minor ongoing per §solicit_mercenaries). The ruler's request for mercenary applicants — handled by recruiters and the marshal. The ruler need not be in any specific settlement; the activity is the act of putting out the word.
- **Call to arms** (minor ongoing; ruler of a realm only, per §call_to_arms). Muster vassals for war; arrival schedule per the muster-delay table from `acore_axioms_strongholds_and_domains.xml` §muster_delay L373-382.
- **Oversee investment** (minor ongoing; 1 day per 500gp per `ax_campaign_play.xml` §oversee_investment). Project decision (2026-05-06): "oversee" here is interpreted as the ruler reviewing books and progress reports; remote-capable. The investment attracts 1d10+1 new families instead of the usual 1d10 per 1,000 gp.

**Out of scope here (live in their location surfaces, NOT in this sub-tab):**

- **Oversee construction** (in the stronghold UI / construction site UI per `gdd-stronghold-construction.md`)
- **Supervise construction** (same — requires Engineering presence)
- **Train troops** / **oversee troop training** / **inspect troops** (in the Garrison sub-tab and stronghold UI; require ruler at the stronghold)
- **Hire mercenaries** (in the Settlement Panel HiringPanel per `gdd-settlement-exploration-ui.md`; requires ruler at the settlement)
- **Military campaign** (launches into the field-combat surface when initiated; cross-cuts; not a Domain-tab decree)

**Senatorial domains** are out of scope per O-D7 — `consult_senate` and senatorial-type rule are not in v1.

### 11.2 Decree card UI

Each card uses a compact layout focused on the order's parameters and dispatch state, not on slot accounting:

```
+-----------------------------------------------------------+
| Issue Decree: Tax rate                       Minor (sing.)|
| Current: 2 gp / family   →   New: [3] gp / family         |
| Effect next month: +1 gp/family revenue · -1 morale roll  |
| [Issue decree]   [Inspect math]                           |
+-----------------------------------------------------------+
```

```
+-----------------------------------------------------------+
| Administer Domain                            Major (ong.) |
| Time today: 6 hours · Banked this month: 12 / 18 days     |
| Effect: +1 morale roll · +5% domain XP                    |
| [Bank today's session]   [Cancel month's effort] (modal)  |
+-----------------------------------------------------------+
```

- Card shows: name, frequency tag, parameter inputs (where applicable), effect summary, RAW-cited "Inspect math" link.
- Singular decrees execute on click and emit a `decree_issued` notification with the resulting effect.
- Ongoing remote activities (administer_domain, manage_henchmen, conscript/levy, solicit, call to arms, oversee_investment) show today's session status (banked / not yet / in progress) and lifetime ticks accumulated. The "Cancel month's effort" affordance for administer_domain raises the standard abandon-confirmation modal per §15.1.6.

### 11.3 Pre-9th-level rulers

Pre-9th-level rulers still have access to all decrees in this sub-tab. Per `acore_axioms_strongholds_and_domains.xml` §before_ninth_level L121 they may still make investments, hire mercenaries, and otherwise direct the domain — they simply do not auto-attract followers or peasants.

### 11.4 Empty / no-domain state

For an active entity who does not rule a domain, the Decrees & Remote Orders sub-tab is hidden from the strip — there is nothing to decree without a domain. Class-specific activities (Faith / Magical Research / Trade / Syndicate / Garrison Training) live in §12 and may still appear for an entity without a domain when the activity is location-bound elsewhere (e.g., a mage's research at a borrowed sanctum).

---

## 12. Class-Specific sub-tab (label varies)

The Class-Specific sub-tab is the central location for high-level activities gated to the active entity's class. The sub-tab label adapts dynamically per §4.4 visibility logic.

### 12.1 Class-bucket matrix

The following matrix maps each class to its applicable buckets. A class may apply to multiple buckets, in which case the sub-tab content stacks blocks for each.

**Per Q14 [RESOLVED 2026-05-11], "Garrison Training" is NO LONGER a class-bucket column.** Troop training (train_troops / oversee_troop_training / inspect_troops) is **proficiency-gated** on Manual of Arms (with combinable Riding / Weapon Focus for cavalry, archers, etc.) or an equivalent class power, NOT class-gated. Those activities now live in the **Garrison sub-tab (§8)** with proficiency-based eligibility. Fighter and other "fighter-flavored" classes that previously appeared here under Garrison Training no longer have a class-bucket entry unless they have another applicable class power.

The Bardic Patronage column replaces the old Garrison Training column and surfaces only for Bards — its content is the two Bard-specific class powers (Chronicles of Battle aura, Solicit Followers).

| Class | Faith | Magical Research | Trade | Syndicate | Bardic Patronage | Notes |
|---|:---:|:---:|:---:|:---:|:---:|---|
| Fighter | | | | | | castle. No class buckets — troop training surfaces in the Garrison sub-tab if Fighter has Manual of Arms proficiency. |
| Mage | | ✓ | | | | sanctum |
| Cleric | ✓ | ✓ | | | | fortified church. Per Q11 [RESOLVED 2026-05-10]: divine casters with full `spell_research` ALSO get Magical Research. Cleric stacks Faith (consecrate / sacrifice / divine power) + Magical Research (research divine spells, scribe scrolls, create divine items). |
| Thief | | | | ✓ | | hideout |
| Dwarven Vaultguard | | | | | | underground vault. No class buckets — troop training surfaces in the Garrison sub-tab via Manual of Arms. |
| Dwarven Craftpriest | ✓ | ✓ | | | | underground vault; cleric-equivalent for divine. Per Q11: divine + spell_research → stacks Faith + Magical Research. |
| Elven Spellsword | | ✓ | | | | fastness; arcane caster. Troop training via Manual of Arms in the Garrison sub-tab. |
| Elven Nightblade | ✓⁻ | ✓ | | ✓ | | hideout; arcane caster + thief class (✓ Syndicate per RAW class-id allowlist). Per Q11: also has spell_research → Magical Research. |
| Assassin | | | | ✓ | | hideout. Per Q14 [RESOLVED 2026-05-11]: Syndicate detection is now a class-id allowlist matching RAW `acore-campaign-hijinks.xml` §hijinks-eligibility (thief, assassin, elven_nightblade). Assassin's fighter combat-progression no longer excludes them. |
| Bard | | | | | ✓ | hall. **Bardic Patronage** is its own bucket per Q14, replacing the prior "Bardic Patronage variant of Garrison Training" model. Content: Chronicles of Battle aura (RAW `acore_campaign_classes.xml` §hireling_inspiration L569-575, L5+) + Solicit Followers (RAW §hall L577-584, L9+). Bards are NOT hijink-eligible. Bards CAN train troops if they take Manual of Arms proficiency — that surfaces in the Garrison sub-tab, NOT here. |
| Bladedancer | ✓ | | | | | temple; divine + martial-flavor. Per Q11+Q14: Bladedancer has `spell_research_and_minor_item_creation` (Faith bucket, restricted research stays inside Faith) — NOT the full `spell_research` keyed for Magical Research. Per Q14: no Garrison Training bucket (troop training is in Garrison sub-tab if Bladedancer takes Manual of Arms). |
| Explorer | | | | | | border fort; borderlands/wilderness only. No class buckets — troop training via Manual of Arms in Garrison sub-tab. |
| Anti-Paladin | | | | | | dark fortress; lawful-evil/chaotic warrior. Per O-D4 (mirror of Paladin), Anti-Paladin does NOT cast divine magic and has no Faith block — `data/classes/anti_paladin.json` confirms (no `divine_casting` power). Per Q14: no Garrison Training bucket. Tab hidden for Anti-Paladin unless they take a proficiency / class power that grants a bucket. |
| Barbarian | | | | | | chieftain's hall. No class buckets. |
| Dwarven Delver | | | | | | underground vault. Per Q14: no class buckets — Delver has thief combat-progression and stronghold_underground_vault (NOT stronghold_hideout), so not on the syndicate allowlist; no casting; troop training (if any) lives in the Garrison sub-tab. Tab hidden. |
| Dwarven Fury | | | | | | underground vault. No class buckets. |
| Elven Courtier | | ✓ | | | | elven fastness; arcane caster (arcane_casting_in_armor). |
| Elven Enchanter | | ✓ | | | | sanctum; arcane caster. |
| Elven Ranger | | | | | | elven fastness. No class buckets. |
| Paladin | | | | | | fortress; lawful warrior. **Per O-D4 resolution:** ACKS Paladins are flavored on Roland / Lancelot / El Cid — they do **not** cast magic and do **not** research magic. Per Q14: also no Garrison Training bucket. Tab hidden. |
| Priestess | ✓ | ✓ | | | | cloister. Per Q11: divine + spell_research → stacks Faith + Magical Research. |
| Shaman | ✓ | ✓ | | | | medicine lodge. Per Q11: divine + spell_research → stacks Faith + Magical Research. |
| Warlock | | ✓ | | | | coterie |
| Witch | ✓ | ✓ | | | | coven. Per Q11 [RESOLVED 2026-05-10]: Witch is a divine caster (per `data/classes/witch.json` which has `divine_casting`) but builds coven strongholds and may build dungeons just as mages do. Stacks Faith + Magical Research. |
| Lightblessed Wonderworker | ✓ | ✓ | | | | sanctum (per Q5 resolution); arcane primary + divine secondary (Mage at root for domain purposes per `domain-roadmap-corrected.md` §10 [RESOLVED 2026-05-06]; stacked-block model — Magical Research expanded, Faith collapsed). Aspirant follower rules per §12.7 (50/50 mage/cleric split per Q2; standard sanctum 1d6-month-then-throw rule per Q13 [RESOLVED 2026-05-10] — INT-modified for mage aspirants, WIS-modified for cleric aspirants). |
| Darkblood Ruinguard | | ✓ | | | | dark fortress (renamed from "Zaharan Ruinguard" for IP reasons; mechanics unchanged). Per Q12 [RESOLVED 2026-05-10]: Darkblood is an arcane caster (`data/classes/darkblood_ruinguard.json` has `arcane_casting_in_armor`, NOT `divine_casting`) with very limited research at L10+. Stronghold is identical to a Fighter's stronghold. Per Q14: no Garrison Training bucket. |
| Venturer | | | ✓ | | | guildhouse; mercantile-class |

A class with NO checkmarks in the matrix above does not see the Class-Specific sub-tab at all per §4.4. **Per Q14, many fighter-flavored classes (Fighter, Paladin, Anti-Paladin, Barbarian, Explorer, Dwarven Vaultguard, Dwarven Delver, Dwarven Fury, Elven Ranger) have NO checkmarks and the Class-Specific tab is correctly hidden for them.** This is the architecturally-correct outcome — they have no class-specific high-level activities; their Domain-tab interaction lives in Overview / Stronghold / Garrison / Realm / Treasury / Decrees / Encounters / Departure Log.

### 12.2 Faith block (divine casters)

Surfaces the `<category name="divine">` activities from `ax_campaign_play.xml`:

- **Congregants** — current count + a card summarizing growth: "1d10 + Charisma bonus per 1,000gp spent proselytizing during the prior month's campaign activities" per §congregant_growth. The block tracks proselytizing-gp committed and shows the projected congregant gain at next monthly resolution
- **Divine power accumulator** — current divine-power gp value held by the spellcaster, per §extract_divine_power. Shows extraction history and the weekly cap (10gp per 50 congregants; +0-8 per 10 families if ruling a domain)
- **Activities** —
  - Dispatch missionaries (minor restricted, monthly cap; gp tracking for next-month congregant growth)
  - Cast charitable spells (minor singular; gp value tracking from spell-cost tables for next-month congregants)
  - Consecrate altar (major ongoing; 1 day per 500gp; level 5+; aura size 100 sq ft per 100gp)
  - Consecrate fields (major ongoing; level 5+; 1 day per 780 peasants; expends 2gp divine power per family; success increases land value +1 next month)
  - Consecrate ruler (major restricted, yearly cap; level 9+; spiritual advisor of the ruler; expends divine power equal to monthly domain revenue; success: +1 base morale, +1 vassal loyalty rolls, double-vagary rolls for 12 months)
  - Extract divine power (minor restricted, weekly cap; 50+ congregants required)
  - Perform blood sacrifice (minor restricted, daily cap; **chaotic only**)
  - Perform ceremonial sacrifice (minor restricted, daily cap; **lawful only**)
- **Religious authority** — when this caster is the ruler of a domain: per `acore_axioms_strongholds_and_domains.xml` §tithes the dominant religion of the domain is the caster's religion (cleric/bladedancer specifically). Religious-conversion mechanics surface here per §new_religion (the −4 first-month / −2 thereafter penalties; conversion via Dedicated morale or half-population convergence)
- **Faithful followers garrison status** — cross-reference to the Garrison sub-tab's "Faithful (no wages)" indicator per `acore_axioms_strongholds_and_domains.xml` §garrison

**Location-gating:** Most divine activities require the caster to be at their consecrated altar / temple / cloister. Singular activities (cast charitable spells, extract divine power, perform_blood_sacrifice, perform_ceremonial_sacrifice, dispatch missionaries) require presence only at execution time. **Ongoing activities follow the tick-tolerance rule per §15.1.1:**
- Consecrate altar (1 day per 500gp of altar) — at altar; tick-tolerance window equals days already invested
- Consecrate fields (1 day per 780 peasants) — anywhere in domain; tick-tolerance applies
- Consecrate ruler (single performance per year, but ongoing in execution) — at the ruler's location during the consecration; tick-tolerance applies

Greyed in notebook elsewhere with travel shortcut per §15.4. Stepping away within the tolerance window (≤ days already performed) is permitted; exceeding the window auto-forfeits the activity and divine power expended per §15.1.4.

### 12.3 Magical Research block (arcane casters)

Surfaces the `<category name="magical">` activities from `ax_campaign_play.xml`:

- **Library / sanctum status** — owned spellbooks, scrolls, formulas, magic items in the sanctum
- **Active research projects** — list with project type (researching new spell / creating magic item / performing ritual spell / creating constructs / creating crossbreeds / granting unlife per `ax_campaign_play.xml` §research_magic), gp committed, days/weeks/months remaining, success target, current modifiers
- **Activities** —
  - Research magic (major ongoing; appropriate class/level/equipment required)
  - Rewrite spell (major ongoing; 7 days per spell level; 1,000gp per spell level)
  - Replace spell (major ongoing; 7 days per spell level; 1,000gp per spell level)
  - Scribe spell (major ongoing; 7 days regardless of level)
  - Manage assistant (trivial restricted; level 9+; supervise INT-bonus assistants while performing magical activities)
- **Apprentices and seekers** — per `acore_core_classes.xml` §Mage: 1d6 apprentices + 2d6 normal-men seekers. Apprentices and seekers are tracked here. Loyalty/morale per `<loyalty_or_morale_rules>`: 1d6-month dropout chance for seekers; apprentice loyalty handled per henchman rules
- **Magic-assisted construction** — when the active entity is a stronghold-builder mage, surface the spells available for construction-rate boosts per `gdd-stronghold-construction.md` §2 (Move earth: 12,500gp/turn on ditches/moats/ramparts; Transmute rock to mud: +50% rate for 3d6 days; etc.)
- **Mage-specific dungeon-under-tower hook** — per `acore_core_classes.xml` §Mage `<acquisition_rules>`, *"If the mage builds a dungeon beneath or near the tower, monsters will start to arrive to dwell within, followed shortly by adventurers seeking to fight them."* Dungeon-construction status surfaces here for Mages, with the resulting domain-encounter modifier (project-designed: dungeon attracts wandering monsters per `ax_domain_level_encounters.xml` §dungeons) so the Encounters & Threats sub-tab can show the increased frequency

**Location-gating:** All four major magical activities (research_magic, rewrite_spell, replace_spell, scribe_spell) are **ongoing** per `ax_campaign_play.xml` §magical and require the caster at the sanctum (or borrowed sanctum) under the tick-tolerance rule per §15.1.1. A mage who has invested 12 days at the sanctum on a 30-day research project may step away for up to 12 consecutive days before forfeit; on return within the tolerance window, ticks resume. Departing for longer auto-forfeits the research and the gp committed per §15.1.4. Manage assistant (trivial restricted) accompanies a major magical activity and is bound to the same location as the supervised activity. Greyed in notebook elsewhere with travel shortcut per §15.4.

### 12.4 Trade block (Venturer)

Surfaces the venturer's mercantile mechanics and high-level monopoly:

- **Guildhouse status** — per `ax_venturer_class.xml` §stronghold_and_followers: stronghold-as-guildhouse following hideout rules
- **Apprentices** — 2d6 venturer apprentices + the venturer's hired ruffians; loyalty / morale rules per the venturer class
- **Monopoly status** (level 12+) — per `ax_venturer_class.xml` §monopoly: the venturer earns 1gp/month per urban family in the urban settlement where they hold monopoly. Display monopoly settlements, monthly monopoly revenue, and competing-venturer status (per RAW: only one venturer can earn monopoly revenue per urban family)
- **Mercantile ventures cross-reference** — the Settlement Panel per `gdd-settlement-exploration-ui.md` owns the actual buy/sell, solicit-merchants, persuade-merchants flows. The Trade block surfaces summary status (current trade routes active, cargo loads in transit, shipping contracts open) and cross-activates to the Settlement Panel for execution
- **Caravan / fleet management** — when the venturer operates caravans / vessels, summary status here

**Location-gating:** Most mercantile activities require the venturer to be in an urban settlement (with caravan or ship for shipping/passenger work). Singular activities (buy_sell_*, hire_hirelings, persuade_*, enter_market) require presence only at execution time. **Ongoing activities (solicit_merchants, solicit_passengers, solicit_shipping_contracts — each 1-3 weeks)** follow the tick-tolerance rule per §15.1.1: the venturer accumulates ticks each day in the market and may step away for up to that many days without forfeit. Greyed in notebook elsewhere with travel shortcut per §15.4.

### 12.5 Syndicate block (Thief / Assassin / Elven Nightblade)

Surfaces the `<category name="syndicate">` activities from `ax_campaign_play.xml`:

- **Hideout status** — base of operations for hijinks per `ax_campaign_play.xml` §lay_low §plan_hijink
- **Syndicate composition** — list of hijink-capable thieves under the active entity's command (apprentices per `acore_core_classes.xml` §Thief; underbosses; sub-syndicates). Each member's hijink throw status, current activity assignment, lay-low status
- **Activities** —
  - Order hijink (Boss; major or minor depending on assignment scope; assigning to all members at the boss's base = major; small subset = minor; per RAW *"a boss assigns each member one hijink per month and leaves the completion deadline within that month to the perpetrator. Assigning additional hijinks or imposing a deadline triggers a loyalty roll by the member."*)
  - Plan hijink (minor ongoing; 2d8+3 days at base level; 2d6+3 days for level 5+; 2d4+3 days for level 9+)
  - Perform hijink (major; 1 day for plannable hijinks; 3d6+10 days for ongoing hijinks like carousing/disinforming/slandering/spying/treasure_hunting)
  - Lay low (minor ongoing; 2d8+3 days; required after arson/assassination/infiltration/sabotage/smuggling/subversion/stealing per RAW)
  - Await trial / Bribe magistrate / Hire attorney / Interplead (Crime & Punishment cluster — surfaces when a syndicate member or the ruler is caught)
- **Crime & Punishment status** — for any syndicate member currently caught and awaiting trial: their crime, time-languishing remaining, attorneys hired, bribes applied, expected outcome on the Crime & Punishment table
- **Hijink revenue tracking** — accumulator showing this-month-and-last-month hijink yields per type, fed into the Treasury & Ledger sub-tab as `category: "hijink_revenue"` ledger entries per `ax_campaign_play.xml` §hijink_revenue

**Location-gating:** Singular activities (order_hijink as singular major when assigning to all members at base, bribe_magistrate, hire_attorney, interplead) require presence only at execution time. **Ongoing activities follow the tick-tolerance rule per §15.1.1:**
- Plan hijink (2d8+3 / 2d6+3 / 2d4+3 days by level) — at hideout; tick-tolerance applies
- Lay low (2d8+3 days) — at base; tick-tolerance applies. Lay-low is by definition a "remain at base" activity, so the absence-streak rule maps directly to the lay-low concept; exceeding tolerance breaks lay-low and exposes the perpetrator to detection per `ax_campaign_play.xml` §lay_low
- Perform hijink (1 day for plannable; 3d6+10 / 3d4+8 / 2d6+5 days for ongoing types like carousing/disinforming/slandering/spying/treasure_hunting) — at target location; tick-tolerance applies for ongoing variants. Field-execution UI is the future hijink-execution surface; the Domain tab tracks status only
- Await trial (by crime severity) — perpetrator is in jail throughout (not voluntary location-binding; tick-tolerance is moot since the perpetrator cannot leave anyway)

Crime & Punishment activities at courthouse / settlement (singular for bribe / hire-attorney / interplead). Greyed in notebook elsewhere with travel shortcut per §15.4.

### 12.6 Bardic Patronage block (Bard only)

Per Q14 [RESOLVED 2026-05-11], Bardic Patronage is its own class-bucket — replacing the prior "Bardic Patronage variant of Garrison Training" model. Troop training is no longer a class-bucket concern; it lives in the Garrison sub-tab (§8) with proficiency-based eligibility.

This block surfaces two Bard-specific class powers from `acore_campaign_classes.xml`:

- **Chronicles of Battle aura status** — passive ability per `acore_campaign_classes.xml` §hireling_inspiration L569-575 ("Any henchmen and mercenaries hired by the bard gain +1 morale if the bard is present to witness and record their deeds. This bonus stacks with modifiers from Charisma or proficiencies."). The block displays the active aura status (which hirelings/mercenaries currently benefit, the +1 morale stacking applied) and the bard's current location relative to those units. This is **NOT a launchable activity** — it applies passively when the bard is in the same hex/army as eligible units. The block shows the aura as a status indicator only.
- **Solicit Followers** — Ongoing 1-3 weeks per `acore_campaign_classes.xml` §hall L577-584 (unlocked at Bard L9 when the bard establishes a hall). On completion, recruits 1d4+1×10 0th-level mercenaries plus 1d6 1st-3rd-level bards into the ruler's service. Hire requires standard mercenary wages.
- **Recruitment history** — last solicitation outcomes (this month + last month), current hireling/mercenary roster summary cross-linked to the Garrison sub-tab.

**Class-restricted note** — Bardic Patronage is restricted to the Bard class. Bards are NOT hijink-eligible per `acore-campaign-hijinks.xml` §hijinks-eligibility (which restricts hijinks to assassins, elven nightblades, and thieves), so the Syndicate block is unavailable to Bards regardless of their thief combat-progression family. Bards CAN train troops if they take the Manual of Arms proficiency — that surfaces in the **Garrison sub-tab (§8)**, not here.

**Location-gating:** Solicit Followers is **ongoing** per the 1-3 week duration. The bard accumulates ticks each day spent at the recruitment location (typically the bard's hall, in the urban settlement nearest the bard's domain) and may step away within the tick-tolerance window per §15.1.1. The Chronicles of Battle aura applies passively wherever the bard is — no location-gating on that.

### 12.6.1 [REMOVED — troop training is no longer a class-bucket activity]

The original §12.6 "Garrison Training block (fighter-progression classes)" has been moved to **§8 (Garrison sub-tab)** per Q14 [RESOLVED 2026-05-11]. Troop training is **proficiency-gated** on Manual of Arms (with combinable Riding / Weapon Focus enabling different troop types) or an equivalent class power, not class-gated. Fighter, Paladin, Anti-Paladin, Barbarian, Explorer, Dwarven Vaultguard / Delver / Fury, Elven Ranger, Bladedancer — and Cleric, and any other character who takes Manual of Arms — train troops via the Garrison sub-tab's proficiency-gated launchers. The activities themselves (`train_troops`, `oversee_troop_training`, `inspect_troops`) are unchanged; only their UI surface has moved.

See §8 for the relocated content (training queue, eligibility checks, launcher cards).

### 12.7 Lightblessed Wonderworker hybrid block (per Q20 [RESOLVED 2026-05-11])

The Lightblessed Wonderworker (renamed from "Nobiran Wonderworker" for IP reasons; mechanics unchanged from `pc_classes_5.xml`) is a unique class with no `<stronghold_and_followers>` section in `pc_classes_5.xml`. Per Q20 [RESOLVED 2026-05-11] the project-designed hybrid is:

- **Stronghold:** sanctum + dungeon (mage-style; mage-rooted progression for domain purposes)
- **Followers:** 1d6 1st-3rd-level apprentices + 2d6 0th-level normal-man aspirants per `pc_classes_5.xml` §stronghold_sanctum L127-134
- **Apprentice / aspirant class split:** the 1d6 apprentices and 2d6 aspirants are split **50/50 mage/cleric by default** (player may rebalance the split at sanctum founding to reflect their leanings; the rebalance is captured as a `wonderworker_split_pct` value on the stronghold record at completion). The 50/50 baseline aligns with the RAW phrase "1d6 mages or clerics" and is the project-canonical resolution.
- **Aspirant creation (Q20):** every 0-level aspirant is created as a 0-level Normal Man. The split is assigned at creation:
  - 50% are **Mage aspirants** — if rolled INT is less than 9, INT is boosted to 9 (the project-designed minimum so the aspirant has a realistic chance at promotion).
  - 50% are **Cleric aspirants** — if rolled WIS is less than 9, WIS is boosted to 9 (same rationale, WIS-flavor).
- **Aspirant promotion (Q20):** after **4 months** of joining the Wonderworker (universal fixed timer, equal to the average of the standard sanctum's 1d6-month variability), each aspirant rolls a single d20 + ability modifier:
  - **Mage aspirants** roll **d20 + INT mod**. 14+ promotes to 1st-level Mage. 13 or less leaves the sanctum.
  - **Cleric aspirants** roll **d20 + WIS mod**. 14+ promotes to 1st-level Cleric. 13 or less leaves the sanctum.
- **There is no monthly attrition.** The prior 1d6/month-for-6-months mechanic (from O-D5) is fully scrapped. The promotion throw at month 4 is the sole attrition check.
- Each year the Wonderworker dwells in the sanctum, an additional 1d6 0-level aspirants arrive (split 50/50 again per the founding rebalance), up to a maximum of 6 apprentices and 12 normal men studying at any one time per the standard sanctum cap.
- Aspirant lifecycle tracking lives in the `followers` table with `source_kind='aspirant'`, `character_class='normal_man'`, `level=0`, `intended_class='mage'` or `'cleric'`, and `promotion_eligible_day = joined_calendar_day + 112` (4 months × 28 days on the project calendar; corrected 2026-06-12 from 120, a 30-day-month slip). Promotion outcomes (success → become 1st-level; failure → leave sanctum) flow into the Departure Log sub-tab.

**Standard Mage / Witch / Warlock / Elven Enchanter sanctums follow the same Q20 mechanic** with single-class intent (e.g., a Mage's 2d6 aspirants are all `intended_class='mage'`). The 4-month fixed timer and d20+ability_mod 14+ throw applies universally; the Lightblessed-specific bits are the 50/50 mage/cleric split, the cleric branch using WIS, and the ability-floor-of-9 at creation.

- **Class-Specific sub-tab content:** stacks Magical Research block (primary, expanded by default) + Faith block (secondary, collapsed by default). Lightblessed plays as a Mage at root for domain purposes (mage progression family per `pc_classes_5.xml` L46) but unlocks the Faith block via its cleric-list divine casting per `pc_classes_5.xml` §divine_casting L87-93 and split apprentice set. Research-project list in the Magical Research block accepts targets on EITHER the arcane spell list OR the cleric divine spell list per `pc_classes_5.xml` §spell_research L121-123 + §arcane_casting + §divine_casting; at level 11+ the dual-list access extends to ritual spells per §ritual_magic_and_advanced_creation L135-137.

**Tag:** The aspirant promotion mechanic at month 4 with a single d20 + ability-mod 14+ throw is **Arbiter-specific simplification** of the RAW 1d6-month-variability standard sanctum rule (`acore-campaign-hijinks.xml` §sanctums L534-538) — fixed-4-months is the expected-value collapse so the timing is deterministic and consistent across all sanctum classes. The 50/50 mage/cleric Wonderworker split and the cleric-aspirant WIS-modified throw are also Arbiter-specific (no ACKS sourcebook publishes the Wonderworker split or WIS-vs-INT differentiation). The class itself is RAW per `pc_classes_5.xml` (with the IP-driven name change).

### 12.8 Class-Specific sub-tab tab strip rendering

When a class has multiple applicable buckets (e.g., Bladedancer = Faith + Garrison Training), the Class-Specific sub-tab is a single sub-tab containing stacked blocks. The blocks render as collapsible cards within the sub-tab — the player can expand the block(s) they want to focus on and collapse the others.

When a class has a single bucket, the sub-tab is named for that bucket (e.g., "Magical Research" for a pure Mage). The single-block content fills the sub-tab page area with the stacked-block-card UI used for multi-bucket cases (the rendering is consistent; only the tab label differs).

---

## 13. Encounters & Threats sub-tab

The Encounters & Threats sub-tab surfaces external threats to the domain: wandering-monster incursions, dungeon-monster influence, dangerous-borders configuration, bandit alerts, occupation / pillage status, and active sieges.

### 13.1 Layout sections

1. **Threat status header** — at-a-glance current-threat summary:
   - "All clear" / "Bandits active" / "Invasion in progress" / "Domain occupied" / "Domain pillaged this month" / "Under siege" — the highest-severity active threat
   - Time-since-last-encounter readout
   - Encounter-throw frequency for this domain (daily / weekly / monthly per `ax_domain_level_encounters.xml` §classification_rules — Wilderness daily, Borderlands weekly, Civilized monthly)
2. **Dangerous borders configuration** — per `ax_domain_level_encounters.xml` §dangerous_borders:
   - Current configuration: Isolated / Spearhead / Flank / Line (Judge-determined; project-designed: setting-generation outputs the initial configuration; player adjusts when borders change due to invasion / annexation / vassal acquisition)
   - Effective territory for encounter throws (per the table mapping actual territory + configuration → effective territory)
   - Visual indicator of which borders are secured vs. unsecured (cross-references the regional hex map per `gdd-terrain-system.md`)
3. **Stronghold and garrison sufficiency for encounter throws** — per `ax_domain_level_encounters.xml` §strongholds_and_garrisons:
   - If civilized/borderlands with insufficient garrison/stronghold → treat as one classification worse for encounter throws (Civ → Bord; Bord → Wild)
   - If wilderness with insufficient → treat borders as one level more dangerous
   - If already-isolated wilderness with insufficient → suffers one encounter throw of 1d6 every day for every 6-mile hex (catastrophic)
   - Display the current effective frequency given sufficiency/insufficiency
4. **Dungeon morale impact** — per `ax_domain_level_encounters.xml` §dungeons:
   - List of dungeons within the domain territory (cross-references dungeon-layout system per `gdd-dungeon-layout.md`)
   - Each dungeon shows: monster XP total, families-in-territory divisor, computed morale penalty (XP / families, rounded to nearest whole)
   - Cumulative morale penalty applied to base morale
   - "Garrison expenditure to mitigate" — per RAW: each gp/family increase in garrison reduces dungeon morale penalty by 1 point. Status shows current mitigation gp/family and remaining penalty. Cross-references Garrison sub-tab for spend adjustment
   - Note: domains with unmitigated dungeon morale penalty count as **unsecured** for neighboring domains' dangerous-borders calculations per RAW
5. **Recent encounters** (chronological list of domain encounters, last 12 months default, configurable):
   - Date / time of encounter
   - Encounter creature type (per `ax_domain_level_encounters.xml` encounter generation: 1d8 column → sub-table → 1d12 specific creature)
   - Lingering vs. migrating (% In Lair check)
   - Number encountered
   - Reaction outcome (Hostile / Unfriendly / Neutral / Mercantilist / Friendly per §reactions)
   - Resolution (defeated by garrison / pillaged-then-departed / settled in dungeon / drove off / traded / etc.)
   - Domain consequences (population loss, treasury loss, pillage damage to land improvements, morale roll modifier applied next monthly resolution)
6. **Active threats** (anything that is currently an ongoing threat — distinct from resolved past encounters):
   - Bandits (when current morale ≤ −2 per `acore_axioms_strongholds_and_domains.xml` §bandits): current bandit count, projected damage, NPC challenger status (cumulative chance per month per morale level — Rebellious 10%/mo, Defiant 5%/mo, Turbulent 1%/mo)
   - Occupation: enemy army occupying domain (turns counter; cumulative −1/month morale penalty up to −4 per §invasion_and_occupation)
   - Pillage: enemy army pillaging domain (one-time −4 morale penalty, alternative to occupation; per §pillage)
   - **Active siege (v1: abstract resolution; mapped tactical sieges per Domains at War: Battles are out of project scope).** Two RAW-supported abstract resolution paths surface differently on the card depending on who's involved (per the dispatcher in `docs/domain-roadmap-corrected.md` Phase 8 siege subsystem):
     - **Player-involved sieges** use the full DaW: Campaigns rules per `daw_sieges.xml` §blockade L65-193, §reduction L195-463, §assault L465-499. The siege card surfaces: current phase (blockade / reduction / assault), besieging-army composition, defender garrison, current SHP / max SHP (with damage delta), breach count from reduction (1 per 1,000 shp damage per §siege_mechanics.breaches L42-46), unit_capacity derived per the no-map formula at `daw_sieges.xml` §siege_mechanics.unit_capacity L37-41 (`ceil(shp / 1000)`; the future grid-builder per `gdd-stronghold-construction.md` §4 will replace this with the per-structure sum in v1.1+), supplies remaining (default 600 gp/point of unit_capacity ≈ 10 weeks at full garrison; ±un-blockaded prep additions per §effects_of_blockade L116-136), required encirclement units, and expected resolution timeline.
     - **NPC-vs-NPC sieges** use the Sieges Simplified table per `daw_sieges.xml` §sieges_simplified L813-846+. The siege card surfaces a more compact off-camera view: besieging-army size, defending-army size, unit_advantage delta, projected days-to-capture from the duration table, current elapsed days, and proportional shp remaining derived from elapsed-time per §off_camera_and_intervention_guidance L838-844. If a PC subsequently arrives at the besieged stronghold, the engine escalates the siege to the full DaW rules (state reconstructed proportionally) and the card swaps to the player-involved layout.
     - In both cases the card cites the relevant `daw_sieges.xml` section in an Inspect-math link so the player can see the procedure being applied.
   - Lingering monsters: monsters that lingered after a domain encounter and are now part of the domain's terrain (potentially in a dungeon); morale penalty per §monsters-settle
7. **Reconnaissance status** — per `ax_domain_level_encounters.xml` §reconnaissance:
   - Current intelligence on monsters / armies in or near the domain
   - "Poor reconnaissance" warning when the player's intel is incomplete (RAW: ruler may remain unaware of monsters until pillaging or stronghold-arrival)
   - Cross-reference to scout / explore-hex activities and any reconnaissance-rolling mechanics (project-designed integration with the future scouting / exploration system)
8. **Response controls**:
   - **Deploy garrison** — when an encounter or invasion is active. Cross-activates Garrison sub-tab with the active threat highlighted; player chooses which units deploy
   - **Begin military campaign** — cross-activates the §11 Military Campaign activity to formally launch a campaign against the threat
   - **Negotiate** — when reaction is Mercantilist or Friendly, opens a sub-flow for trade / hire-as-mercenaries / hire-as-henchmen offers (per §reactions, friendly monsters can be offered positions with +2 bonus)
   - **Repress** — when bandits are present (cross-references Garrison sub-tab repression spend)

### 13.2 Encounter notification and routing

Domain encounters fire as `EventBus.log_entry_added` entries with `category: "system"` and `metadata.event_type: "domain_encounter"`. They appear in the Unified Log's All tab and in this sub-tab's Recent Encounters list. High-severity events (active siege starting, domain pillaged, NPC challenger emerged) additionally trigger a HUD notification toast per `gdd-ui-architecture.md` §2.7. The toast offers a click-action that cross-activates this sub-tab.

### 13.3 Chaotic-domain encounter context

For a chaotic domain per `ax_domains_of_chaos.xml`, the alignment-modifier for reaction rolls flips:
- Lawful or neutral monsters encountering chaotic domain: −2 (doubled if monster BR > garrison BR)
- Chaotic monsters encountering chaotic domain: +2

This sub-tab applies the right modifier per RAW automatically.

---

## 14. Departure Log sub-tab

The Departure Log sub-tab is the chronological permanent record of significant losses and changes affecting the domain. Analogous in spirit to the Henchmen tab Departure Log per `gdd-henchmen-tab.md`.

### 14.1 Logged event types

The canonical event-type list lives in the migration 121 `CHECK` constraint on `domain_departure_log.event_type` and is mirrored in `DepartureLogRecorder.VALID_EVENT_TYPES`. The two are kept in lockstep per `coding_conventions.md` §57. The descriptions below explain when each type fires; the codes are the literal `event_type` values written to the log.

- `established` — a new domain is created (any path: grant / purchase / conquest / clear / clanhold_annex / recruit_chieftain). Written by Phase 11B's `LifecycleHandler.record_establishment` after `EstablishDomainFlow.establish_domain` inserts the row.
- `classification_advanced` / `classification_regressed` — per `acore_axioms_strongholds_and_domains.xml` §classification_advancement L165-175 + §optional_rules.regression L178. Both written by Phase 11A's `DepartureLogRecorder.record_monthly_transitions` after the monthly tick detects the change.
- `morale_tier_dropped` — Phase 11A: when the named morale tier (`Stalwart` / `Steadfast` / `Dedicated` / `Loyal` / `Apathetic` / `Demoralized` / `Turbulent` / `Defiant` / `Rebellious` per `acore_axioms` §effects_of_morale L538-549) transitions DOWNWARD. Intra-tier moves (e.g., -5 → -6 both Rebellious) do not log. Upward recovery does not log.
- `territory_lost` — Phase 11B: hex(es) released from the domain via conquest, abandonment, or cession.
- `stronghold_lost` — Phase 11B: stronghold falls to 0 SHP (collapse), is voluntarily demolished, or is captured by an enemy.
- `defeat` / `pillaged` — battles lost where the garrison was destroyed/repulsed; pillage events. Wired in 11B alongside the lifecycle handler when the Phase 9A encounter/bandit summaries are surfaced.
- `ruler_changed` / `ruler_died` — the active entity dies or transfers domain rule. Domain persists across the change; the log records the predecessor.
- `succession_started` / `succession_resolved` / `succession_lapsed` — Phase 11C: ruler-death + grace-period state machine entries.
- `vassal_lost` / `vassal_promoted` — vassal henchman dies, defects, declares independence, is replaced (lost), or is elevated within the realm (promoted).
- `religion_converted` — domain religion changes per `acore_axioms` §tithes L245 "Changing religion is possible but causes severe morale penalties." Phase 11D wires the project-designed conversion process; this is the entry that records the start AND completion of the conversion arc.
- `monster_settled` — wandering monsters settle in a dungeon and impose ongoing morale penalty per `ax_domain_level_encounters.xml`.
- `calamity` — utter catastrophe (−4 morale roll) per `acore_axioms` §calamities; ruler exile; succession war; etc.
- `conquered` — Phase 11B: terminal event where the domain passes to an enemy ruler (`same_campaign_npc`) or is lost to a foreign realm (`lost_to_foreign`).
- `abandoned` — Phase 11B: domain abandoned (voluntary player action; ruler-bankrupt; stronghold-collapse grace lapsed without rebuild).
- `restored` — Phase 11B: domain returns to `active` lifecycle state after `ruined_stronghold` rebuild within grace.

### 14.2 Layout and interaction

The sub-tab is a virtualized chronological list (most-recent first), with filter / search / export per the established Unified Log pattern. Each entry shows date, event type, summary, and an "Inspect" button that opens a modal with full event details (cause, consequences, related ledger entries, related encounter records).

The Departure Log is **append-only** — entries are not deleted or edited. This preserves narrative weight per the established project convention (see `gdd-henchmen-tab.md` §6.3).

---

## 15. Activity-execution architecture (Q8 hybrid model)

This section establishes the canonical activity-execution model for the Domain tab and any future location-context surfaces. It applies to every executable activity surfaced in §11 Activities, §12 Class-Specific, and any activity buttons elsewhere in the Domain tab.

### 15.1 The hybrid model

Per Q8 resolution, the Domain tab is the **master inspection-and-execution surface** for v1, with location-context shortcut surfaces deferred to v1.1+.

**Notebook (Domain tab) responsibilities:**
- Always available regardless of where the active entity is
- Source of truth for activity state (configured parameters, in-progress projects, accumulated progress, history)
- Always allows configuration of activity parameters even when location-gated
- Greyed execute-button state when location is wrong, with a tooltip explaining the requirement and an optional travel shortcut
- Surfaces the same set of activities as future location panels (location panels are shortcuts, not replacements)

**Future location-context panels (v1.1+):**
- Modeled on the existing Settlement Panel architecture (per `gdd-settlement-exploration-ui.md`)
- Triggered when the active PC arrives at their stronghold / hideout / sanctum / temple / etc.
- Provide quick-access buttons for the most-frequent class-appropriate activities at that location
- Read state from and write to the same source of truth as the Domain tab — they are not parallel data stores

### 15.1.1 The "tick tolerance" rule for ongoing activities

**This is the canonical mechanic for ongoing-activity persistence in v1.** Per `ax_campaign_play.xml` §frequency_types: *"Ongoing activities require more than one game day and must be performed throughout the listed time period."*

> **Scope clarification (2026-05-06):** Tick-tolerance, daily-tick accumulation, and the abandon-and-resume model **apply ONLY to activities with `frequency = "ongoing"`** per `ax_campaign_play.xml` §frequency_types L159-163. Activities with `frequency = "singular"` (L152-155) and `frequency = "restricted"` (L156-158) are **atomic** — if interrupted before their full time-cost elapses, they fail entirely and must be restarted from scratch. There is no partial credit for a Singular or Restricted activity. The engine enforces this distinction by using different state machines for the two frequency families per `gdd-realtime-scheduler.md` §4.8.2. The "abandon" affordance shown on activity cards in §11 and §12 is therefore meaningful only for Ongoing activities.

The official Discord judge consensus (confirmed by Jedidiah) refines "performed throughout" for Ongoing activities with a **tick-tolerance** mechanic:

> For every ongoing activity, the requisite time must be spent on it (Major or Minor time-cost depending on the activity) for the day to count. **Each day on which the entity is at the required location and the daily session fires uninterrupted earns one "tick"** toward completion (tabletop judges use literal "/" marks on a paper calendar). After the daily session is banked the entity is free to use the day's remaining active hours however they like without affecting that day's tick. **The character may step away from the task** across days without immediately forfeiting, **BUT if cumulative absence exceeds days-spent-on-task, the progress and gp committed are forfeited** and the activity must be restarted from scratch.

**Crucially, absence is cumulative for the full lifetime of the activity — it never resets while the task remains in progress.** A character who steps away, returns, then steps away again carries forward all prior absence days. This produces a clean derived property: **a task can never take more than 2× its default duration in real elapsed time.** If a 14-day research project ever reaches 14 days of absence, it must already have 14 ticks — meaning it has completed; otherwise it would have forfeited at absence = 15.

**Worked example: magical research.** A mage at L11 starts a 45-day research project on Day 1. On Day 1 they select Magical Research as their primary activity for the day. The engine schedules a 6-hour `ongoing_session_complete` event at fire_time = day_start + 6 hours. Nothing interrupts; the event fires, `daily_ticks_accumulated = 1`, and the mage is now free to spend the rest of the day's active hours camping, training a henchman, or whatever. On Day 2 they're called away at hour 4 to defend the stronghold from raiders; the day's session is interrupted before the 6-hour fire_time, no tick is banked for Day 2, but the 1 tick from Day 1 is preserved. `absence_accumulated` increments by 1. The research continues; the mage just needs to make up the lost day before cumulative absence catches up to ticks.

### 15.1.2 Tick-tolerance state model

Project-designed engine state per ongoing activity:

```
ongoing_activity_state {
  id: String                      # the activity instance
  entity_id: String               # who's performing it
  activity_def_id: String         # what activity (e.g., "research_magic")
  required_location: LocationRef  # where it must be performed
  total_days_required: int        # the activity's RAW completion length (= target ticks)
  ticks_accumulated: int          # days actually performed at location (= progress)
  absence_accumulated: int        # CUMULATIVE days not performing (never resets while in_progress)
  gp_committed: int               # gp spent up front (forfeited on abandon)
  state: "in_progress" | "completed" | "forfeited"
  started_on: int                 # in-game tick
}
```

**Daily scheduler boundary update** per active ongoing activity (evaluated at end-of-day):

- **Entity at required location AND spent the appropriate slot on this activity:** `ticks_accumulated += 1`. (`absence_accumulated` unchanged — does not reset on return.) If `ticks_accumulated >= total_days_required`, mark `state = "completed"` and emit `EventBus.activity_completed`.
- **Entity at required location BUT did not spend the slot on this activity** (e.g., at the sanctum but used the major slot on Rest instead of Research): `absence_accumulated += 1`. Per O-D17 resolution (v1.4): present-but-not-performing counts toward absence the same as physical absence. The activity is in suspension that day.
- **Entity NOT at required location:** `absence_accumulated += 1`.

**Forfeit check** at end of day after the daily update: if `absence_accumulated > ticks_accumulated`, mark `state = "forfeited"`, emit `EventBus.activity_forfeited` with cause "absence exceeded ticks," log via `EventBus.log_entry_added`, and forfeit gp committed.

**Tolerance remaining** at any point in time: `ticks_accumulated - absence_accumulated`. This is the number of additional consecutive (or non-consecutive) days the entity may be absent before the next forfeit check fails. It can be zero or briefly negative just before forfeit; the engine evaluates strict inequality (`absence > ticks`) so absence exactly equal to ticks is still safe.

### 15.1.2.1 Worked example (per Jedidiah)

A mage Abel starts a 14-day Magical Research project on Day 1.

| Period | Days | Action | ticks | absence | Tolerance |
|---|---|---|---|---|---|
| Phase 1 | 1–5 | At sanctum, performs daily | 5 | 0 | 5 |
| Phase 2 | 6–9 | Away for 4 days | 5 | 4 | 1 |
| Phase 3 | 10 | Returns and performs | 6 | 4 | 2 |
| Phase 4 | 11–14 | At sanctum, performs daily | 10 | 4 | 6 |
| Phase 5 | 15 | Away again | 10 | 5 | 5 |

At the end of Phase 5: ticks=10, absence=5. He has 4 more days of research needed (10 of 14 done). Tolerance remaining = 10 − 5 = 5 days.

If an orc invasion now requires 5 days of travel:
- Days 16–20: traveling away → absence increments daily, reaching absence=10 by end of day 20. ticks remain 10. Tolerance remaining = 10 − 10 = 0. Activity is not yet forfeited (`absence > ticks` is false; equal is safe).
- Day 21: arrives at the conflict point but is still away from sanctum → absence = 11 > ticks = 10 → **forfeit**. The research is cancelled, gp committed is lost.

Abel must therefore choose between completing the research (return to sanctum, accept lost time defending, perhaps abandoned domain) or going to fight the orcs (forfeit research). This is the design intent: high-level characters have weighty long-term commitments, and their adventuring choices have to account for them.

### 15.1.3 Location requirements during the activity

- **At specific structure** (sanctum / altar / hideout / cloister / construction site / where troops are training): the required location is that structure
- **In domain (anywhere)** (consecrate_fields, conscript_troops, levy_militia): the required location is "anywhere within the domain"; movement within the domain does not increment cumulative absence
- **With the army** (military_campaign): the required location is "with the army" — a moving location; absence is measured from the army's position
- **Trivial ongoing exception** (manage_henchmen): per RAW, manage_henchmen explicitly allows changing assignments "whenever the henchman is accessible physically or magically." Treat manage_henchmen as having **no required location** — it never accumulates absence. This is the canonical exception.

Each per-activity spec in §11 and §12 notes whether the tick-tolerance rule applies and at what location.

### 15.1.4 Outcomes when the entity leaves during an ongoing activity

The tick-tolerance rule means departure does not immediately terminate the activity. Three outcome paths:

1. **Return before forfeit** (`absence_accumulated <= ticks_accumulated`): the entity returns to the required location. On the next day spent performing the activity, `ticks_accumulated` increments. **`absence_accumulated` does NOT reset** — it carries forward. No data is lost; no modal fires; the activity simply resumes with reduced tolerance going forward.
2. **Exceed tolerance** (`absence_accumulated > ticks_accumulated` after a daily increment): the engine auto-forfeits the activity at the day-boundary tick when this inequality first becomes true. Progress and gp committed are lost. Logs the forfeit with cause "absence exceeded ticks." The entity may restart from scratch later. **No modal fires for auto-forfeit** — the player was already warned pre-departure if the trip was projected to exceed tolerance; auto-forfeit is the consequence of the player having chosen Yes anyway, or having extended the absence beyond original projection, or having let cumulative absence over multiple trips reach the threshold.
3. **Voluntary explicit abandon** (player clicks "Abandon" on activity card): regardless of current absence state, the player can deliberately end the activity. Raises the abandon-confirmation modal per §15.1.6 (canonical copy). On Yes, terminates the activity and forfeits. On No, dismisses the modal and the activity continues in its current state.

**Forced departure** (e.g., NPC abducts the entity, magical compulsion, forced narrative events) — the engine treats forced departure exactly like a voluntary departure: tick-tolerance applies, absence accumulates, and forfeiture occurs only if absence exceeds ticks per the same model. There is no special "involuntary forfeit" path; the system is uniform.

### 15.1.5 Pre-departure warning for over-tolerance trips

The engine compares projected trip duration against the **remaining tolerance window**, not just total ticks. The remaining window is `ticks_accumulated - absence_accumulated` (the number of additional absent days the activity can survive before forfeit).

When the player initiates travel (or any action that would take the entity away from the required location) AND `(absence_accumulated + projected_trip_days) > ticks_accumulated`, the engine raises the abandon-confirmation modal per §15.1.6 *before* the travel begins. The modal explains that the trip will exceed remaining tolerance and gives the player the option to abandon-and-travel or cancel-the-trip.

When `(absence_accumulated + projected_trip_days) <= ticks_accumulated`, the engine does **not** raise a modal — the player is free to depart and return; the engine accumulates absence as the trip unfolds.

Because absence is cumulative, a player who has previously stepped away from the activity has *less* tolerance for the next trip than a player who has been continuously present. The activity card always shows the current remaining tolerance so the player can plan around it (§15.1.7).

If during the trip the player extends their absence beyond what was originally projected (e.g., stays longer than planned, takes a side adventure), the activity may auto-forfeit per §15.1.4 outcome path 2. The activity card surfaces an escalating-warning UI so the player has running visibility.

### 15.1.6 Abandon-confirmation modal (canonical copy)

This modal raises in three cases: (1) player clicks "Abandon" on the activity card; (2) player initiates travel (or other interrupting action) that the engine projects will exceed the tolerance window; (3) player attempts another action that would consume the ~8-hour daily active-work budget already committed to this ongoing activity (per `gdd-realtime-scheduler.md` §4.8.1). The modal does NOT raise for routine within-tolerance travel.

**Single-activity case** (one ongoing activity affected):

```
WARNING: Taking this action will abandon <ongoing_task_name>
and forfeit progress, proceed anyway?

  [Yes, forfeit progress]   [No, <ongoing_task_name>]
```

The `<ongoing_task_name>` placeholder is filled with the user-facing display name of the activity (e.g., "Research: Detect Magic", "Plan hijink: Carouse at Aerendel Tavern", "Oversee Construction: Watchtower"). The "No, ..." button label includes the activity name so the player sees explicitly what they're choosing to keep doing.

**Multi-activity case** (more than one ongoing activity would be affected):

```
WARNING: Taking this action will abandon the following
ongoing activities and forfeit progress, proceed anyway?

  • Research: Detect Magic (8 / 30 ticks; tolerance 8 days, trip 14 days)
  • Plan hijink: Carouse (4 / 17 ticks; tolerance 4 days, trip 14 days)

  [Yes, forfeit progress]   [No, keep activities]
```

The multi-activity variant lists each affected activity with its current tick count, total duration, and the tolerance-vs-trip comparison so the player sees why each one is at risk. The "No" button uses the plural "keep activities" form.

**Modal behavior:**
- Modal is non-bypassable — always raises when an over-tolerance interrupting action is attempted, even if the player has "Suppress confirmations" preferences set elsewhere
- Modal is keyboard-accessible: Enter defaults to the safe "No" choice; Escape closes the modal as if "No" were chosen
- Project-designed: a small subtitle below the warning may show gp-forfeited and ticks-lost (e.g., *"Forfeiting will lose 1,500gp committed and 8 ticks of research progress"*); informational, not part of the canonical copy

**Voice / tone:** "abandon" and "forfeit progress" are deliberately imperative because the choice is irrevocable per RAW (no pause/resume; restart from scratch).

### 15.1.7 Activity-card UI for tick-tolerance state

The activity card surfaces tolerance state across three visual stages:

**While the entity is at the required location and performing daily** (in-progress / on-track):

```
+-----------------------------------------------------------+
| ⚙ Research: Detect Magic        Major (ongoing)           |
| Progress: 8 / 30 ticks (8 days at sanctum)                |
| Estimated 22 days remaining if performance continues      |
| 1,500 gp committed                                        |
| [Abandon activity]  [Inspect math]                        |
+-----------------------------------------------------------+
```

**While the entity is away from the required location, within tolerance** (amber warning):

```
+-----------------------------------------------------------+
| ⚙ Research: Detect Magic        Major (ongoing)           |
| ⚠ Currently absent — within tolerance                     |
| Progress: 8 / 30 ticks                                    |
| Cumulative absence: 3 days  ·  Tolerance remaining: 5 days|
| Forfeit at: 9 days cumulative absence                     |
| [Plan return travel]  [Abandon now]  [Inspect math]       |
+-----------------------------------------------------------+
```

**While the entity is away and tolerance is about to be exceeded** (red urgent — fires when `ticks_accumulated - absence_accumulated <= 1`):

```
+-----------------------------------------------------------+
| ⚠⚠ Research: Detect Magic        Major (ongoing)          |
| URGENT — return within 1 day or activity will be          |
| forfeited and 1,500 gp committed will be lost             |
| Progress: 8 / 30 ticks                                    |
| Cumulative absence: 8 days  ·  Tolerance remaining: 0 days|
| [Plan return travel]  [Abandon now]  [Inspect math]       |
+-----------------------------------------------------------+
```

After auto-forfeit, the activity is moved to the Departure Log per §14 with cause "absence exceeded ticks" and removed from the active activity list.

### 15.1.8 Consequence: travel may precede or interrupt ongoing activities

The implication for player flow: the tick-tolerance window is the canonical mechanic for letting players step away briefly without restarting. Concrete patterns:

- **Begin at the right location** — same as before. Activity starts; tick accumulation begins immediately. Each day at location performing = +1 tick.
- **Step away briefly within tolerance** — the engine tracks absence; no modal fires; ticks pause; on return, ticks resume. Net cost: the trip days don't count toward progress, so the activity takes longer in real-time, but no progress is lost.
- **Step away beyond tolerance** — the engine raises the §15.1.6 modal pre-departure if the projected trip exceeds tolerance. Player chooses to abandon-and-go or stay-and-continue. If the player extends the trip beyond original projection, the activity may auto-forfeit during the extended absence.

This is the Q8 hybrid model's revised flow: **configure anywhere, travel to location, execute, optionally step away within tolerance, return and resume — OR abandon and restart.**

### 15.2 Location-gating decision tree per activity

For each activity surfaced in the Domain tab, the location requirement is determined by the activity's RAW definition. This GDD's per-activity specs in §11 and §12 declare the location requirement explicitly. The general patterns:

For **singular** activities (single game day; one execution within the day): location must be correct **at execution time**. The entity is free to depart immediately after, since the activity completes within the day.

For **ongoing** activities (multiple days): location must be correct at the start, and the entity must accumulate ticks at the location per the **tick-tolerance** rule in §15.1.1. The entity may step away within the tolerance window (`absence_accumulated <= ticks_accumulated`) and return to resume; absences exceeding the tolerance forfeit the activity per §15.1.4.

**Location categories:**
- **In personal domain (tick-tolerance applies for ongoing):** administer_domain (ongoing), issue_decree (singular), conscript_troops (ongoing), levy_militia (ongoing), oversee_investment (ongoing), oversee_construction (ongoing), supervise_construction (ongoing). For ongoing variants, the ruler accumulates ticks each day they spend the appropriate slot somewhere within the personal domain. Movement within the domain is permitted; departing the domain begins accumulating absence.
- **At specific structure (tick-tolerance applies for ongoing):** research_magic / scribe / rewrite / replace (sanctum); consecrate_altar (altar); plan_hijink / order_hijink / lay_low (hideout); train_troops / oversee_troop_training (stronghold where troops are based for ongoing variants). Singular variants like inspect_troops require presence only at execution time.
- **At urban settlement (singular and ongoing variants):** hire_mercenaries, buy_sell_* are singular; solicit_*, persuade_* may be ongoing variants — for ongoing solicits, tick-tolerance applies (must remain in market for the duration, with tolerance window). Cross-references Settlement Panel
- **In domain (anywhere; tick-tolerance applies for ongoing):** consecrate_fields (cleric accumulates ticks anywhere within the domain); military_campaign (with the army — a moving location; ticks accumulate while with the army)
- **Trivial ongoing exception (manage_henchmen):** no required location per RAW — the activity description allows reassignment whenever the henchman is accessible. This activity does not accumulate absence; its tolerance is effectively unbounded.
- **At target location (not domain; field execution):** perform_hijink — the perpetrator's location is the target site; tick-tolerance applies for ongoing hijink variants (3d6+10 / 3d4+8 / 2d6+5 days).

### 15.3 Execute button states (UI specification)

For each activity-execute button:

| State | Visual | Tooltip | Action on click |
|---|---|---|---|
| **Active** | Standard button styling | Activity description + cost (game-hours per `gdd-realtime-scheduler.md` §4.8.1) | Schedule the activity via `ActivityTimeCostExecutor`, log the event, update state |
| **Daily budget exhausted (overtime)** | Standard styling with amber strenuous-day icon | "Daily ~8h active-work budget already spent. Launching this activity counts the day as overtime per §4.8.5; further days of overtime accrue strenuous-day penalties." | Schedule the activity normally; the strenuous-accountant accumulates the overtime day per `gdd-realtime-scheduler.md` §4.8.5 |
| **Wrong location** | Greyed with location icon | "Available at {location_name}. Currently in {current_location}. Travel: {n} days." | Optional "Plan travel" link to the travel system |
| **Insufficient gating** | Greyed with class/proficiency icon | "Requires {gating_description}" (e.g., "Requires Engineering proficiency"; "Requires level 5+"; "Requires fighter attack progression") | No action |
| **Insufficient resources** | Greyed with treasury icon | "Insufficient gp ({available} / {required}gp)" or similar resource specifier | No action |
| **Already in progress (entity at required location, performing)** | Standard styling, "Abandon" label instead of "Begin" | "{ticks} / {total} ticks. Absence: {absence} days. Tolerance remaining: {ticks - absence} days. Click to abandon. **Progress and gp committed are forfeited.**" | Raises abandon-confirmation modal per §15.1.6; on Yes, terminates the activity and logs the abandon with cause "voluntary"; on No, dismisses |
| **Already in progress (entity at location, did not perform today)** | Standard styling with absence-counted note | "{ticks} / {total} ticks. Absence: {absence} days (today counted as absence per O-D17 — daily active-work budget spent on other activities). Tolerance remaining: {ticks - absence} days." | Same abandon flow; the activity does not advance and absence accumulates per O-D17 |
| **Already in progress (entity absent, within tolerance)** | Amber warning styling, "Plan return travel" / "Abandon now" | "Currently absent {N} days cumulative. Tolerance remaining: {ticks - absence} days. Forfeit at {ticks + 1} cumulative absence." | "Plan return travel" opens travel UI; "Abandon now" raises §15.1.6 modal |
| **Already in progress (entity absent, tolerance about to be exceeded)** | Red urgent styling | "URGENT — return within 1 day or activity forfeited. {gp_committed}gp will be lost." | Same options as amber state, with visual escalation |
| **Forfeited via auto-forfeit (absence exceeded ticks)** | Removed from active list; entry in Departure Log | n/a — activity is terminated | n/a — restart from scratch if the entity wants to attempt again |

### 15.4 Travel shortcut behavior (pre-execution)

This sub-section covers travel **before starting** an ongoing activity. Travel **during** an ongoing activity is governed by the tick-tolerance rule in §15.1 — short trips within tolerance need no warning; trips that would exceed tolerance raise the §15.1.6 modal.

When a wrong-location greyed button shows a "Plan travel" link, clicking it:
1. Opens the travel-planning UI (per `gdd-party-tab.md` §6 Travel sub-tab) pre-populated with the destination
2. The player confirms or modifies the travel plan and dispatches the party
3. On arrival at the destination, the same activity button reactivates automatically (state-driven; the button uses the entity's current location signal)
4. The engine may emit an `EventBus.activity_reachable(activity_id)` notification when an entity arrives at a location that newly enables a previously-greyed activity, surfaced as a HUD toast

Player flow: notebook → see greyed button → click travel → travel → arrive → notebook button is active → execute → remain at location to accumulate ticks (or step away within tolerance and return per §15.1.4).

### 15.4.1 Travel during in-progress ongoing activity

The tick-tolerance rule (§15.1.1) governs this case. The engine evaluates the projected trip duration against each in-progress ongoing activity's tolerance:

- **Trip duration ≤ remaining tolerance for all affected activities:** no modal fires; the player departs freely; the engine accumulates absence during the trip; on return, ticks resume (with reduced tolerance going forward, since absence carries forward).
- **Trip duration > tolerance for one or more affected activities:** the §15.1.6 abandon-confirmation modal raises *before* travel begins, listing each affected activity and showing the tolerance-vs-trip comparison. The player chooses to abandon-and-travel (Yes, forfeit progress) or stay-and-continue (No).
- **Mid-trip extension beyond original projection:** if the player extends an already-acceptable trip beyond what the engine originally projected (e.g., picks up a sub-quest that pushes the absence past tolerance), the activity may auto-forfeit at the day-boundary tick when absence first exceeds ticks per §15.1.4. The activity card surfaces escalating-warning UI (§15.1.7) so the player has running visibility.

Multi-party travel: if multiple party members are traveling together but only one of them has ongoing activities at the departure location, the modal scopes to that entity's activities. Other party members travel normally. If multiple party members each have ongoing activities affected by the trip, the engine raises one modal per affected entity (sequenced) so the player decides per-entity.

### 15.4.2 The tick-tolerance rule supersedes the v1.2 strict-abort behavior

v1.2 specified strict abort-on-departure per a stricter reading of the RAW "performed throughout" clause. v1.3 supersedes that with the **tick-tolerance** rule per Discord judge consensus (confirmed by Jedidiah). The strict-abort behavior is no longer the v1 design.

Pause-and-resume is now mechanically **bounded** rather than absent: a character can step away for up to `ticks_accumulated` consecutive days and resume on return, but exceeding that window forfeits the activity. This is the canonical RAW-aligned mechanic.

Open question O-D15 has been re-resolved with the tick-tolerance disposition (see §22).

### 15.5 Henchman-vassal activity-on-behalf

Per `ax_campaign_play.xml` §manage_henchmen: *"A henchman generally performs any campaign activities he is capable of on behalf of his employer."* The Domain tab supports this via:
- The active entity may be a henchman vassal — switching active entity is the way to inspect and direct that henchman's domain
- From the henchman's Domain tab, the player can configure activities the henchman will perform
- The henchman is presumed to be at their own domain when ruling it; location-gating for the henchman's activities respects the henchman's location, not the player's
- This is the player's **delegation model**: the player issues directives via the henchman's Domain tab; the engine executes on behalf of the henchman during monthly resolution

This design avoids the awkwardness of a player needing to "physically" travel a henchman to their own domain — the henchman lives there.

### 15.6 Future v1.1+ location panel hooks

When future location-context panels are added (Stronghold-Adjacent Panel, Sanctum Panel, Hideout Panel, Temple Panel, etc.):
- They consume the same activity catalog as the Domain tab
- They highlight a curated subset of "most-frequent" activities at that location for the active entity's class
- They cross-activate to the Domain tab for full configuration / history when needed
- They use the same source of truth and state model
- They are not required for v1 — Domain tab is sufficient for full functionality

The future Stronghold-Adjacent Panel GDD will spec the per-structure activity curation. Until then, all activity execution flows through the Domain tab.

---

## 16. Lifecycle interactions

### 16.1 Domain establishment

Per `acore_axioms_strongholds_and_domains.xml` §domain_acquisition, domain establishment paths:

- **Civilized:** land grant from a local ruler (typical), or purchase at 50gp/acre, **or conquest** (per Jedidiah's correction during synthesis)
- **Borderlands or Wilderness:** clear lairs and wandering monsters, **or conquest** (annexing existing domains), **or wilderness annexation of a clanhold** per `ax_domains_of_chaos.xml` §chaotic_realms (*"A ruler with an existing realm of any type may annex a clanhold to that realm."*)
- **Chaotic-domain establishment** (chaotic ruler, opt-in at establishment): per `ax_domains_of_chaos.xml` §establishment — instead of clearing beastmen, recruit a clanhold chieftain as henchman; if unsuitable, replace with sub-chieftain; once clanhold chieftain is brought into service, adventurer becomes chaotic domain ruler

The establish-domain UI flow (project-designed) is invoked from the Domain tab empty-state. It branches by classification, by alignment, and by class restrictions (Explorer borderlands/wilderness only; dwarves/elves race-restricted territory).

### 16.2 Classification advancement and regression

- **Advancement** per `acore_axioms_strongholds_and_domains.xml` §classification_advancement: requires all hexes at prior classification's max + urban settlement of 20% population threshold + within distance of friendly city/town. Surfaced in Overview sub-tab §6.1 progress section
- **Regression** per §regression (optional rule): classification can drop back if the conditions that justified advancement end. Surfaced in Departure Log when triggered

### 16.3 Monthly resolution

Per `ax_campaign_play.xml` §monthly_cycle, the engine processes domains in three stages per game month:

**Start of month:**
- Domain growth (adventuring + investment + random)
- Congregant growth (for divine spellcasters)
- Revenue collection (land + service + tax + tribute + special tax + loans + investment + hijink revenue)

**Campaign activities (mid-month):**
- Random events (favors and duties d20 roll for vassals; vagaries-of-recruitment when applicable; other vagaries; wandering monster encounter throws scheduled per week / day; event allocation)
- Per-week procedure (4 weeks): weekly random events, daily activities

**End of month:**
- Expense payment (living expenses, hireling wages, domain expenses, settlement expenses, congregant expenses, tribute, special taxes, loans)
- Domain morale roll (each domain rolls 2d6 + base morale + monthly event modifiers per §monthly_event_modifiers)

The Domain tab subscribes to scheduler boundary events for each stage. The Treasury & Ledger sub-tab logs each revenue / expense entry. The Overview sub-tab logs growth-roll outcomes. The Encounters & Threats sub-tab logs encounter throws.

### 16.4 Conquest and abandonment

Phase 11B implements the foundation; Phase 11D-prereq.0b revised the conquest taxonomy to the three defender-POV outcomes used today. The `domains.lifecycle_state` column (migrations 122 + 125) is the canonical authority: `active` / `ruined_stronghold` / `succession_pending` / `abandoned` / `salted_to_ruin`. Monthly tick skips terminal-state rows (`abandoned` / `salted_to_ruin`); rows persist for the audit history.

**Conquest** — when an enemy successfully takes a domain by force (per `daw_sieges.xml` + `daw_campaigning_armies.xml` §occupation_and_conquest). The Phase 9A `EventBus.siege_concluded(siege_id, outcome)` signal with `outcome in ['captured', 'surrendered']` triggers a two-step pipeline:

1. **`RealmRepository.resolve_conquest_outcome(defender_domain_id, attacker_owner_id, attacker_intent)`** classifies the result into one of three outcomes from the defender's POV. `attacker_intent` is one of `occupy` / `loot_and_scoot` / `salt_the_earth` — derived by `DomainHandlers._derive_attacker_intent` (v1 heuristic: hostile + chaotic → salt; hostile alone → loot; otherwise → occupy) or surfaced via UI for player attackers.
2. **`LifecycleHandler.conquer_domain(domain_id, calendar_day, outcome, new_owner_id, pillage_severity, summary)`** applies the outcome:
   - **`occupied`** — domain row persists with hexes + (post-pillage) population preserved; ownership reassigns to `new_owner_id`. The new owner may be an existing tracked NPC, a PC, or — when the attacker is off-map — the head NPC of a realm just instantiated via `RealmRepository.instantiate_realm_for_off_map_force`. At this layer all three look the same.
   - **`looted_local_succession`** — attacker took the treasury and left; the Realm Substrate's `spawn_local_succession_npc` minted a placeholder local ruler before this call; population reduced 10% via light pillage; stronghold shp reduced 25%; treasury looted to 0; land values decrement 1 (floored at 1).
   - **`salted_to_ruin`** — the only genuinely terminal outcome per DaW salt-the-earth pillage rules. Hexes release, stronghold reduces 50%, population reduces 25%, treasury looted to 0, land values decrement 2 (floored at 1). Lifecycle state flips to `salted_to_ruin`. Row stays for audit; monthly tick skips.

Pillage damage is applied uniformly via `RealmRepository.apply_pillage(domain_id, severity)` with severity 0 (no-op for clean occupy), 1 (light, looted_local_succession default), or 2 (heavy, salt-the-earth default). Vassals always cascade to `departed`. A Departure Log `conquered` entry records the outcome + new owner + pillage result + siege id.

**Single-player note:** there is no `player-vs-player` conquest path in v1. ACKS Arbiter is single-player; multi-PC parties share the player's role. The `new_owner_id` parameter is polymorphic (any character_id is acceptable), so a hypothetical future multiplayer mode reaches PC-vs-PC conflict by setting `new_owner_id` to a hostile PC's character_id — no code path change required.

**Abandonment** — voluntarily abandoning a domain: player flow on the Overview sub-tab's "Domain Management" card. Confirmation modal explains consequences (treasury liquidates to the ruler's coin via `add_coins_cp`, peasants disperse, hexes release back to the unowned pool, vassals become independent, stronghold reverts to ruined-or-available). The modal requires the player to type the domain name as a destructive-action gate. `LifecycleHandler.abandon_domain(domain_id, today, "voluntary", owner_id)` performs the mutation; a Departure Log `abandoned` entry records the reason + liquidation summary.

**Stronghold collapse** — when a stronghold's shp reaches 0 via siege, `EventBus.stronghold_destroyed` with `cause='siege'` triggers `LifecycleHandler.mark_stronghold_collapsed(...)`. The domain enters `ruined_stronghold` state with a 1-game-month grace window (`ruined_stronghold_grace_until_day`). If the stronghold is rebuilt to ≥ 1 shp before the grace lapses, `restore_from_ruin` flips state back to `active`. Otherwise the monthly-tick's `tick_lifecycle_state` auto-fires `abandon_domain(..., REASON_STRONGHOLD_COLLAPSED)` with treasury forfeit (no rebuild ⇒ no stronghold to retrieve cp from).

### 16.5 Ruler death and succession

Per the [RESOLVED 2026-05-06] addendum the succession grace period is **1 game-month**. Phase 11C ships the full state machine in `engine/subsystems/domains/ruler_death_handler.gd`; this section describes the flow from the player's perspective.

**Trigger.** `EventBus.character_died(character_id)` (already emitted by combat, override, and crime resolvers) bridges through `DomainHandlers._on_character_died` into `RulerDeathHandler.handle_ruler_death(deceased_character_id, calendar_day)`. The handler sweeps every active domain owned by the deceased and transitions each into `lifecycle_state='succession_pending'` with `succession_pending_until_day = calendar_day + 30`. Per-domain `succession_started` signals fire plus one consolidated `ruler_died` signal carrying the affected domain ids.

**Status header banner.** The Domain Status header surfaces an `⚠ Succession pending` banner with the grace day + the current heir-designation state. The banner instructs the player to use the Overview sub-tab's Domain Management card to designate or confirm.

**Heir designation.** The Overview sub-tab's Domain Management card shows two new buttons during `succession_pending`: **Designate Heir…** and **Confirm Succession Now**. The picker modal queries `RulerDeathHandler.eligible_heirs_for(domain_id)` and lists candidates with kind chips (`pc` / `henchman` / `non_henchman`), name, class, and level. Selecting a row + pressing Designate writes `designated_heir_character_id` + `designated_heir_kind` to the domains row and emits `succession_heir_designated`. Lifecycle state stays `succession_pending`.

**Resolution.** Two paths reach `RulerDeathHandler.resolve_succession(domain_id, calendar_day)`:
- **Manual confirm** — player presses Confirm Succession Now on a domain with a designated heir.
- **Automatic on grace expiry** — the monthly tick calls `tick_succession_grace(domain_data, calendar_day)`; if `calendar_day >= succession_pending_until_day` and a heir is designated, resolution auto-fires.

Resolution dispatch:
- **Designated heir present** — ownership transfers to the heir; `lifecycle_state` returns to `active`; `designated_heir_*` columns clear. A `succession_resolved` log entry records the new owner + heir_kind. **Non-henchman heirs** carry `base_loyalty_modifier = -2` per `acore_axioms_strongholds_and_domains.xml` §non_henchman_vassals L392-397; the modifier is captured in the log entry's `full_details_json` so future Dynasties / loyalty consumers can read it back.
- **No designated heir + independent domain** — `LifecycleHandler.abandon_domain(domain_id, calendar_day, REASON_NO_HEIR, "")` fires. Treasury forfeit (no recipient). A `succession_lapsed` log entry precedes the `abandoned` entry.
- **No designated heir + vassal domain** — reverts to overlord under direct rule per the v1 default. The vassal_assignment terminates, `liege_domain_id` clears (the domain is no longer a vassal), and ownership transfers to the overlord PC. This is a placeholder for the eventual ACKS Dynasties bloodline-heir model (see `memory/project_dynasties_succession.md`); the underlying state machine + designation columns are already shaped to accept a future bloodline-heir resolver.

**Eligibility.** `eligible_heirs_for(domain_id)` returns active characters in the campaign, filtered by character_type (`pc` / `henchman`). Non-henchman NPC candidates are deferred until the setting-generator layer ships; the eligibility helper exposes the `non_henchman` kind in its API so future generators slot in without changing the UI contract.

**Multi-domain rulers.** A ruler with N domains generates N `succession_pending` rows on death, each with its own independent grace clock. The player may designate different heirs per domain or let some lapse to abandonment / reverts-to-overlord.

### 16.6 Construction completion and stronghold transitions

Construction completion events from `gdd-stronghold-construction.md` §6 (monthly progress) fire `EventBus.stronghold_construction_completed`. The Domain tab's Stronghold sub-tab subscribes and updates:
- Stronghold value (sufficient if minimum threshold reached → stronghold sufficiency morale penalty cleared)
- Followers arrival per `acore_axioms_strongholds_and_domains.xml` §followers_arrival (50% at half-stronghold, +25% at completion, remainder during first month after; only for level 9+ rulers)

Half-stronghold milestone is detected when in-progress construction passes the 50% gp-cost threshold; the engine schedules follower arrivals across the month accordingly.

---

## 17. Cross-tab interactions

Recap of cross-tab activations involving the Domain tab (forward-references the §2 invocation list and adds back-references):

| Source | Action | Target |
|---|---|---|
| Henchmen tab → Roster row right-click | "Manage Domain" (vassal henchmen only) | Domain tab on that henchman |
| Realm sub-tab vassal row click | Switch active entity | Domain tab on vassal |
| Character tab Status sub-tab | "Open Domain Tab" button | Domain tab on same entity |
| Troops tab → unit row right-click | "View in Domain" | Domain tab Garrison sub-tab |
| Settlement Panel → mercantile flows | Treasury entry created | Domain tab Treasury sub-tab |
| Stronghold construction completion | Status updated | Domain tab Stronghold sub-tab |
| Domain encounter notification | Action click | Domain tab Encounters & Threats sub-tab |
| Domain morale critical notification | Action click | Domain tab Overview sub-tab |
| Domain tab Realm sub-tab → Add vassal | Domain assignment | Henchmen tab synced (henchman now flagged as vassal) |
| Domain tab Garrison sub-tab → unit click | Cross-activate | Troops tab Roster filtered |
| Domain tab Stronghold sub-tab → "Commission new" | Cross-activate | `gdd-stronghold-construction.md` commission pipeline |
| Domain tab Activities → "Hire mercenaries" | Cross-activate (settlement-only) | Settlement Panel HiringPanel |
| Domain tab → Inspect math button on any activity | Inspect modal | Inline modal with RAW citation + math breakdown |

---

## 18. Multi-party scope

Per `gdd-ui-architecture.md` §3.9 and `gdd-management-notebook.md` §9, the notebook is per-party. The Domain tab is per-entity within per-party scope:

- **Domains belong to entities, not parties.** A PC's domain follows that PC across party switches. A henchman-vassal's domain follows the henchman. When a party-selector tab is switched, the Domain tab refreshes to show the new party's active entity's domain
- **A PC who switches parties keeps their domain.** Their Domain tab content is identical regardless of which party they're currently a member of
- **Multiple PCs in the same party can each have their own domain.** Each PC's Domain tab shows their own domain when they are the active entity
- **Multiple PCs in the same party can be in the same realm.** If PC-A is overlord of PC-B (via vassalage), PC-B's Domain tab shows their own domain (which is a vassal domain in PC-A's realm); PC-A's Domain tab Realm sub-tab lists PC-B's domain as a vassal entry
- **Cross-party realm complexity:** if PCs in different parties hold domains in interconnected realms (e.g., a sub-vassal of a non-active-party PC), the Domain tab uses the realm graph to show vassal/overlord relationships across parties. Switch-party + switch-active-entity navigation works the same way

### 18.1 Dungeon and combat contexts

PartySelectorTabs is disabled in dungeon and combat per `gdd-ui-architecture.md` §3.9. The Domain tab is scoped to the in-context party only during these phases. Domain-tab activities that require physical presence at a domain are necessarily greyed during dungeon / combat (the active entity is in a dungeon or combat scene, not at their stronghold).

The notebook itself is openable in PC_AWAITING_INPUT combat sub-states per `gdd-management-notebook.md`, so a player can inspect their domain status mid-combat — but cannot initiate location-gated activities.

---

## 19. Empty-state

The Domain tab has multiple empty-state variants based on active entity status. All variants follow the per-Q7 tailored-by-class principle.

### 19.1 Active entity does not yet hold a domain

This variant applies at any level — domain ownership is not level-gated (see §19.2). It is titled separately from §19.2 only because the pre-9 case adds a banner on top of this same content.

Full-tab empty-state with class-tailored acquisition guidance. The page area shows:
- Headline: *"You have not yet established a domain."*
- Acquisition options card per the active entity's class. The card is a pre-filled form keyed to class:

For **Fighter / Paladin / Anti-Paladin / Vaultguard / Spellsword / Bladedancer / Barbarian / Ruinguard / Dwarven Fury** (fighter-progression class with castle/fortress/hall/dark-fortress/vault/fastness/temple stronghold):
- Path 1: Land grant from a local ruler (cite §domain_acquisition; default for civilized territory)
- Path 2: Purchase civilized land at 50gp/acre
- Path 3: **Conquest** (any classification; per Jedidiah's synthesis correction)
- Path 4: Clear borderlands/wilderness territory of lairs and wandering monsters

For **Mage / Warlock / Witch / Elven Enchanter** (sanctum / coterie / coven):
- Same paths as fighter-progression, plus class-specific note: *"You may build a sanctum (typically a great tower). If you build a dungeon beneath or near the tower, monsters will arrive — and adventurers will follow."* per `acore_core_classes.xml` §Mage

For **Cleric / Bladedancer / Priestess / Shaman** (church/temple/cloister/lodge):
- Same paths plus: *"You may establish or build a fortified church/temple/cloister/medicine lodge. If currently in favor with your deity, you may buy or build the structure at half price."* per `acore_core_classes.xml` §Cleric (cleric-specific divine-favor discount)

For **Thief / Assassin / Elven Nightblade** (hideout):
- Same paths plus: *"You may establish a hideout. Successful thieves use their followers to start a Thieves' Guild."* per `acore_core_classes.xml` §Thief
- Note for Nightblade: *"At least one of your apprentices is an infiltrator working for local rivals."* per `acore_demihuman_classes.xml` §Nightblade
- Note for Assassin: hideout per `acore_campaign_classes.xml` §Assassin

For **Explorer** (border fort):
- Path 1 (land grant) NOT AVAILABLE — Explorer stronghold restricted to borderlands or wilderness per RAW
- Path 2 (purchase) NOT AVAILABLE for the same reason
- Path 3 (conquest) available for borderlands/wilderness territory only
- Path 4 (clear lairs in borderlands/wilderness) is the canonical Explorer path

For **Dwarven classes** (Vaultguard / Craftpriest / Delver / Fury):
- Civilized/borderlands paths gated to dwarven-race areas only per `acore_axioms_strongholds_and_domains.xml` §classification
- Wilderness path always available

For **Elven classes** (Spellsword / Courtier / Ranger):
- Same race-gating as dwarven, with elven-race areas
- Note: fastness "must blend seamlessly with nature" per `acore_demihuman_classes.xml` §Spellsword

For **Venturer** (guildhouse via hideout rules):
- Standard paths (any classification)
- Note: *"At level 12+, you may seize monopoly power in an urban settlement and earn 1gp per urban family per month even if you do not rule the domain."* per `ax_venturer_class.xml` §monopoly

For **Bard** (hall):
- Standard paths
- Per the [RESOLVED 2026-05-06] addendum to `domain-roadmap-corrected.md` §10: Bard does NOT train troops as a fighter does (RAW gates `oversee_troop_training`/`train_troops` to fighter-progression). Empty-state notes: *"Your hall attracts mercenaries and bardic followers. Your presence in battle inspires hired troops (+1 morale aura). Use the Bardic Patronage block in the Class-Specific sub-tab to solicit followers and track your aura."*

For **Lightblessed Wonderworker** (sanctum hybrid per Q5):
- Mage paths plus the Wonderworker's hybrid follower note (1d6 1st-3rd-level apprentices split 50/50 mage/cleric + 2d6 0th-level aspirants likewise split, with 1d6/month-for-6-months attrition; player may rebalance the split at sanctum founding)

For **Darkblood Ruinguard** (dark fortress):
- Same as fighter; chaotic flavor

The card is rendered as a pre-filled form because Jedidiah confirmed *"Its just a pre-filled form keyed to class, simple enough."* in Q7 resolution — meaning the empty-state is a class-keyed instructional UI, not a generic handwave.

### 19.2 Active entity is below level 9 (regardless of domain ownership)

If the active entity owns a domain pre-9: full Domain tab content with the pre-9 banner per §6.3.

If the active entity is pre-9 and does not own a domain: empty-state per §19.1 with an additional pre-9 banner: *"Followers and peasants begin arriving at level 9. Until then you may still acquire and develop a domain via [class-specific path summary]."*

### 19.3 Active entity is a humanoid henchman with no vassal domain assigned

Empty-state: *"This henchman does not currently rule a domain. You may assign a domain to this henchman as a vassal from your Realm sub-tab when you have an unassigned domain available."*

If the active entity is a humanoid henchman in a realm with no overlord-PC: edge case (project-designed treatment — may indicate a configuration error). Display a diagnostic message and link to the Henchmen tab for ownership clarification.

### 19.4 Active entity type is invalid for Domain tab

Mercenary Officer, Trained Animal, or Vehicle entity types do NOT have a Domain tab page. Per §3.1, the entity-type dropdown excludes these types when the Domain tab is active. If a programmatic state somehow places one of these types as active when the Domain tab is the active tab (e.g., race condition during tab switch), the tab auto-redirects to the player's preferred PC per §3.1.

---

## 20. Migration plan

There is no current Domain UI implementation per `current_state_ui_audit.md`. The `domains` schema may exist in the database (per `gdd-ui-architecture.md` §3.4 *"`domains` schema exists, no surface"*) but is not currently surfaced.

### 20.1 Current state

- No Domain UI exists in the engine
- `domains` schema may be a stub awaiting full schema design
- Stronghold construction GDD has been authored (`gdd-stronghold-construction.md`) but the construction UI is itself pre-implementation
- Setting generation populates wilderness with beastman clanholds per `gdd-setting-generation.md` §6.5, providing target territory for chaotic-domain or normal-domain conquest paths

### 20.2 Build prerequisites

The Domain tab build requires:
1. **Domain data model schema** finalized (project-designed; covers domain identity, territory hex composition, classification, population, treasury, vassal relationships, morale state, encounter history)
2. **Stronghold construction system** sufficient for the Stronghold sub-tab to consume — at minimum, the structure catalog and the in-progress-construction tracking from `gdd-stronghold-construction.md` §2, §5, §6
3. **Realtime scheduler** monthly boundary events per `gdd-realtime-scheduler.md` (the Domain tab subscribes for monthly-cycle resolution per §16.3)
4. **Henchmen tab and Troops tab** v1.3+ and v2.3+ respectively — for cross-tab activation
5. **Settlement Panel** sufficient for mercantile / hire-mercenaries cross-activation
6. **Setting generation** populating realm political-entities so the active entity can hold a domain within a generated world

The Domain tab is deeply cross-cutting — Phase H+ build per the project's build plan.

### 20.3 Migration steps

1. Finalize and migrate `domains` schema to support the data model implied by this GDD (identity, territory, population, treasury, realm relationships, morale, encounter log, departure log)
2. Build the Domain tab scene (`scenes/ui/management_notebook/tabs/domain_tab.tscn`)
3. Implement the Domain Status header per §5
4. Implement sub-tabs in priority order: Overview → Stronghold → Garrison → Realm → Treasury & Ledger → Activities → Class-Specific → Encounters & Threats → Departure Log
5. Wire D-key keybind via UiInputController per `gdd-ui-shared-services.md` §3
6. Wire monthly-resolution scheduler subscription
7. Wire cross-tab activation entry points per §17
8. Implement empty-state with per-class tailored guidance per §19
9. Implement establish-domain flow (project-designed UI, supporting the conquest + grant + clear paths)
10. Verify chaotic-domain branch end-to-end
11. Verify pre-9th-level branch end-to-end
12. Verify multi-domain (personal + vassal) navigation end-to-end
13. Verify location-gating + travel shortcut for representative activities
14. Verify per-class concern surfacing matches §12.1 matrix

---

## 21. Performance considerations

- **Domain state load:** Each domain's full state may include thousands of ledger entries, hundreds of historical encounters, tens of vassals. Lazy-load per sub-tab activation; virtualize the Treasury & Ledger and Departure Log lists when entry count > 100 (per the Unified Log §15 pattern)
- **Realm aggregate computation:** When a high-tier ruler has many vassals (>50), realm aggregates (total population, total income, vassal-domain morale roll-up) are computed via aggregated SQL queries rather than per-vassal in-memory iteration. Cache aggregates with invalidation on domain-state-change events
- **Monthly resolution simulation:** When the scheduler ticks the end-of-month phase, the engine processes all domains (PC and named-NPC) per `ax_campaign_play.xml` §monthly_cycle. For 100+ domains in a generated realm, processing must be batched and parallelized where deterministic-ordering allows. The Domain tab's UI updates on `EventBus.domain_state_changed` per affected domain rather than blocking on full simulation
- **Encounter table consultation:** Domain encounters require lookup against terrain × classification → encounter sub-table. Cache the lookup tables in memory at session start; the table data is part of the rule-data corpus and does not change at runtime
- **Decree card rendering:** The Decrees & Remote Orders sub-tab renders ~8 cards (the small remote-capable activity set per §11.1). Class-Specific stacks 1-2 buckets with ~5-10 cards each. The Active Projects sub-tab on the Character tab renders only the entity's currently-running ongoing activities, typically ≤5. Negligible render cost across all three; no virtualization needed.
- **Realm sub-tab vassal table:** virtualize when vassal count > 30; otherwise render directly

The Domain tab should add zero noticeable latency to gameplay outside of monthly resolution. Monthly resolution is itself a known scheduler-tick boundary event with its own performance budget per `gdd-realtime-scheduler.md`.

---

## 21.5 Realm Substrate (Phase 11D-prereq.0a)

Phase 11D-prereq.0a introduces an explicit `realms` table + diplomatic-relations layer that supports:
- **Same-realm classification gates** per `ax_domains_of_chaos.xml:76-77` (chaotic clanhold civilized ≤25mi to same-realm city; borderlands ≤50mi).
- **Friendly classification gates** per `acore_axioms_strongholds_and_domains.xml:165, 174` (lawful borderlands ≤72mi to friendly city; civilized ≤48mi). "Friendly" = relation disposition in `{cordial, friendly, allied}`.
- **Conquest-outcome classification** for the 11B siege bridge — distinguishing the three-outcome conquest taxonomy (`occupied` / `looted_local_succession` / `salted_to_ruin`).
- **Foundation for the broader faction system** (Phase 12+) without precluding extension to encounter reactions, hijink targeting, diplomacy proper, settlement control state, trade-route + customs effects.

### Tables

- **`realms`** — one row per realm. `realm_kind='tracked'` realms are in-simulation (have a corresponding apex domain in the campaign); `realm_kind='foreign'` realms are flavor-backdrop entities for off-map conquerors instantiated by Phase 11D-prereq.0b's `instantiate_realm_for_off_map_force` helper. Columns: `id`, `campaign_id`, `name`, `head_character_id` (nullable for foreign realms), `alignment` (nullable for mixed), `dominant_religion`, `culture` (placeholder until the culture system ships), `realm_kind`.
- **`realm_relations`** — pair-symmetric diplomatic-disposition cache. Repository enforces canonical pair ordering (`realm_a_id < realm_b_id` lexicographically) so each pair has at most one row. Disposition is one of `hostile / unfriendly / neutral / cordial / friendly / allied` — six bands mapping loosely to the 2d6 reaction-table outcomes used throughout ACKS. Transitions happen via project-designed events (treaty signed, war declared, embargo lifted), not RAW dice rolls.
- **`domains.realm_id`** — cached pointer to the realm a domain belongs to. NULL means "compute via apex walk" via `RealmGraph.apex_for_domain` as a fallback. The migration backfills this cache for every existing domain via iterative SQL UPDATE.

### Repository — `RealmRepository` (static class in `engine/subsystems/realm_ai/realm_repository.gd`)

Public API:
- `create_realm(data) -> String` — insert helper; used by migration backfill + 11D-prereq.0b's off-map-force instantiation.
- `get_realm(realm_id)`, `get_realm_for_character(character_id)`, `get_realm_for_domain(domain_id)`, `list_realms_for_campaign(campaign_id)`.
- `get_relation(realm_a, realm_b) -> String` — defaults to `neutral`; same-realm queries return `allied` (a realm is allied with itself).
- `set_relation(realm_a, realm_b, disposition, calendar_day) -> bool` — upsert with canonical pair ordering; rejects cross-campaign pairs.
- `resolve_conquest_outcome(defender_domain_id, attacker_owner_id, attacker_intent) -> Dictionary` — the key 11B/11D consumer. Returns `{outcome, new_owner_id, pillage_severity, attacker_realm_id}`. For `occupied` outcomes against an off-map attacker, leaves `new_owner_id` empty in v1; 11D-prereq.0b's siege bridge fills it after calling `instantiate_realm_for_off_map_force`.

### Relationship to RealmGraph (Phase 7)

`RealmGraph` continues to own apex-walking (`apex_for_domain`, `liege_chain`, `is_same_realm`, army-hostility classification). It walks `domains.liege_domain_id` up to the apex domain. `RealmRepository` operates one level up — it asks "what realm is this domain part of?" rather than "what apex domain anchors this chain?" The two coexist: RealmRepository uses the cached `realm_id` (O(1)) and falls back to RealmGraph's apex walk when the cache is empty.

### Deferred to 11D-prereq.0b

- `instantiate_realm_for_off_map_force(culture_placeholder, head_npc_data)` — mints a new `realms` row + head NPC for off-map conquerors choosing to occupy.
- `spawn_local_succession_npc(domain_id)` — placeholder for `looted_local_succession` outcome's new local ruler.
- `apply_pillage(domain_id, severity)` — applies population/treasury/stronghold reductions per the DaW pillage table.
- Retroactive `LifecycleHandler.conquer_domain` signature change to consume the three-outcome taxonomy; `lost_to_foreign` → `salted_to_ruin` rename.

### Deferred to Phase 12 (broader faction system)

- Encounter-reaction modifiers from realm-relations.
- Faction-targeted hijinks (smuggling embargos, espionage cells).
- Diplomatic actions as activities (treaties, alliances, war declarations, embargos).
- Settlement-level control / contested / hostile state.
- Trade-route + customs effects of realm-relations.
- Realm-level economy aggregates.

---

## 21.6 Tithe Apportionment panel (Faction FF-2.3 — added 2026-07-08)

A panel in the Treasury/Realm area of the Domain tab, shown for any domain the
PLAYER rules that has one or more temple factions present. It lets the ruler
divide the domain's RAW tithe expense stream (1 gp/family/month) among those
temples — the persecution/patronage lever of `gdd-faction-framework.md` §6.4.
**That GDD owns the data contract; this section owns only the layout note.**

**Data source.** `TitheApportionment.panel_model(domain_id)` returns:
`{domain_id, pool_gp, shares_sum, has_temples, temples: [ {faction_id, name,
religion_id, congregants, congregant_share_pct, current_share_pct, gp_preview} ]}`.
- `congregant_share_pct` is the **fairness reference** (what a pure congregant
  split would give) — display it beside each temple as the "fair share" anchor.
- `current_share_pct` is the ruler's decreed apportionment (the editable value).
- `gp_preview` is `TitheApportionment.preview_gp(pool_gp, share_pct)` (banker's
  rounding) — recompute per temple as the player moves the steppers.

**Controls.** One integer-point stepper per temple, constrained so the points
**sum to exactly 100** (the Confirm button is disabled while `Σ ≠ 100`). Show a
live gp/month preview per temple (`preview_gp`) and the pool total.

**Confirm.** Issues the SAME shared path NPC rulers use — an
`issue_decree` activity with `decree_kind = "tithe_apportionment"` and
`params.shares = {faction_id: pct}` (the handler routes to
`TitheApportionment.apply`, which re-validates sum-100 + temple-present, persists
`domain_tithe_shares`, writes the ledger, and logs to the event log like any
other decree). Temple reactions (ledger, lobbying) fire identically regardless
of who decreed. No new engine path — the panel is a thin client over the FF-2.3
engine.

**Empty state.** When `has_temples` is false, show "No temples hold congregations
in this domain — the tithe resolves with no recipient" (RAW-consistent: the
faction layer only adds recipients, never changes the expense).

---

## 22. Open questions

- **O-D1.** ~~Manual-override toggle for "active adventuring"~~ **Resolved (v1.5):** No manual flag — heuristic only. The ruler is "active this month" if BOTH (1) they physically left their stronghold during the month AND (2) at least one of: wilderness encounter, entered a dungeon or lair, fought a battle, or fought a siege. Spec implemented in §6.2 Overview Active Adventuring detection.
- **O-D2.** ~~Manual transfer between personal wallet and domain treasury~~ **Resolved (v1.5):** Free if the active entity is at one of the domain's strongholds; impossible otherwise. The treasury is held in the stronghold's vaults; transfers are physical coin movement. Spec implemented in §10.2 Manual transfers.
- **O-D3.** ~~Bard class-specific sub-tab~~ **Resolved (v1.5):** Bards play at the domain tier as Fighter does (Arbiter-specific design — Bards lack the fighter_progression tag in RAW but the Arbiter applies the equivalent capability). Bards see the Garrison Training block (§12.6). Spec implemented in §12.1 matrix and §12.6 class list.
- **O-D4.** ~~Paladin Faith block~~ **Resolved (v1.5):** ACKS Paladins are flavored on heroes like Roland, Lancelot, El Cid — they do NOT cast magic, do NOT research magic, and do NOT have divine spellcasting. They are alternate fighter variants in almost all respects. NO Faith block. Only Garrison Training applies. Spec implemented in §12.1 matrix.
- **O-D5.** ~~Nobiran Wonderworker aspirant dropout rate~~ **Resolved (v1.5, superseded 2026-05-06 and 2026-05-10):** Original O-D5 specified a 1d6/month-for-6-months attrition rate AND an INT-vs-WIS dynamic class-assignment system. **Both are now superseded.** Per Q11/Q12/Q13 [RESOLVED 2026-05-10]: (a) class is renamed to **Lightblessed Wonderworker** for IP reasons; (b) apprentices/aspirants are split **50/50 mage/cleric by default** (player may rebalance at sanctum founding — replaces the INT-vs-WIS dynamic determination); (c) **the standard sanctum 1d6-month-then-14+-throw rule applies** per `acore-campaign-hijinks.xml` §sanctums L534-538 (replaces the 1d6/month-for-6-months mechanic) — mage aspirants throw INT-modified, cleric aspirants throw WIS-modified, success → 1st-level mage or cleric, failure → leave. Spec implemented in §12.7 Lightblessed Wonderworker hybrid block.
- **O-D6.** ~~Domain succession on PC death~~ **Resolved (v1.5):** A new ruler must be appointed within a configurable grace period (default 1 game-month) — even if not a henchman. Successor candidates: another PC, an existing henchman, or (when no henchman is available) a non-henchman NPC populated by the future NPC generator subsystem. If no successor is appointed by the end of the grace period, the domain is treated as abandoned. Cross-GDD coordination flag for the NPC generator. Spec implemented in §16.5 Ruler death and succession.
- **O-D7.** ~~Senatorial domain detection~~ **Resolved (v1.5):** Senatorial-domain types are out of scope for ACKS Arbiter v1. The `consult_senate` activity is removed from §11 Activities. If senatorial-domain support is added in a future expansion, the relevant slot in §11 is reserved for it.
- **O-D8.** ~~Tribute-flow direction~~ **Resolved (v1.5):** Confirmed default — tribute-in (from sub-vassals) is Revenue category `tribute_in`; tribute-out (to lord) is Expense category `tribute_out`. Net tribute is implicit in the headline net-income calculation. Per §10.2 Treasury data model.
- **O-D9.** ~~Investment-revenue category granularity~~ **Resolved (v1.5):** Confirmed default — separate categories: `investment_agriculture` (1d10 new families per 1000gp per `acore_axioms_strongholds_and_domains.xml` §investments) and `investment_urban` (1d10 new urban families per 1000gp per §growing_the_settlement). Per §10.2 Treasury data model.
- **O-D10.** ~~Archetype constraints in the Stronghold sub-tab build flow~~ **Resolved (v1.5):** **Cannot build** a non-conforming stronghold (build flow restricts to class-only archetypes). **Can inherit or take over** a non-conforming stronghold (per `acore_axioms_strongholds_and_domains.xml` §establishing: existing structures may be claimed). **No followers attracted** by a non-conforming stronghold (the per-class follower table is tied to the class-specific structure type). Cross-doc obligation flagged for `gdd-stronghold-construction.md`: clarify (a) how stronghold type is classified during build, and (b) whether converting an existing stronghold from one type to another is supported. Out of scope for this Domain tab GDD; flagged for cross-GDD coordination. Spec implemented in §7.1.1 Non-conforming strongholds.
- **O-D11.** ~~Land Surveyor hireling integration~~ **Resolved (v1.5):** v1 supports option (a) only — the active entity must have Land Surveying proficiency themselves to use the "Survey hex" button. Land surveyor hireling integration (option b) is deferred to the expanded hireling system. Spec implemented in §6.2 Overview editable elements.
- **O-D12.** ~~Vagaries-of-Recruitment integration~~ **Resolved (v1.5):** Confirmed out of scope for the current Domain tab GDD. The Vagaries system (`daw_vagaries.xml`) will be addressed in a future Vagaries integration GDD. The Domain tab does not currently surface vagary outcomes; recruitment activities (conscript_troops, levy_militia, hire_mercenaries, solicit_mercenaries) operate without vagary effects in v1.
- **O-D13.** ~~Realm graph rendering — flat list vs. tree view~~ **Resolved (v1.5):** Flat list for now. Tree view deferred to a future revision if the Realm sub-tab's vassal hierarchy becomes complex enough to warrant the visual. Per §9.1 Vassal list.
- **O-D14.** ~~Military Campaign mid-flight handoff~~ **Deferred (v1.5; revised v1.7 2026-05-06):** The question's framing presupposes a defined boundary between Domain tab and the future combat-tactical surface that does not yet exist. Deferred to the future DaW combat-tactical surface GDD which will define the surface boundaries. Until then, `military_campaign` is launched from the wilderness/army-context UI as an ongoing activity within the tick-tolerance framework (it is field-launched, not remote-capable, so it does not appear on the Decrees & Remote Orders sub-tab per the v1.7 architecture realignment). Per-character running status is surfaced via the Active Projects sub-tab on the Character tab per `gdd-character-tab.md` §3.8; outcomes consume back via Treasury & Ledger and Encounters & Threats. Detailed tactical UI is the combat-tactical surface's domain when authored.
- **O-D15.** ~~Pause-and-resume mechanic for ongoing activities~~ **Re-resolved (v1.3):** **Tick-tolerance per Discord judge consensus** (confirmed by Jedidiah). Each day spent on an ongoing activity earns one tick; the character may step away for up to that many days without forfeit; exceeding the window forfeits progress and gp committed. This supersedes the v1.2 strict-abort behavior. Bounded pause-and-resume IS now part of v1, but limited by the tick-tolerance window. See §15.1.1 through §15.1.8 for the canonical mechanic.
- **O-D16.** ~~Grace period for departed-location ongoing activities~~ **Resolved (v1.3):** Subsumed by the tick-tolerance rule per O-D15 re-resolution. The tolerance window IS the grace period — equal to days already invested. Involuntary departures (forced narrative events, magical compulsion) follow the same tick-tolerance rule as voluntary departures; there is no separate "involuntary" path.
- **O-D17.** ~~Present-but-not-performing edge case~~ **Resolved (v1.4):** Present-but-not-performing **counts toward absence accumulation** the same as physical absence. Per Jedidiah: "Same resolution as not being present." Justification: the daily-tick mechanic measures *days of work performed on the activity*; days where the entity is at the location but does not spend the appropriate slot on the activity are not days of work, so they do not earn ticks AND they consume the same tolerance budget that physical absence consumes. Rationale matches the cumulative-absence design intent — taken together with the never-resets-while-in-progress rule, this produces the clean 2× max-duration property: a task can never take more than 2× its base duration in real elapsed time without forfeiting.

---

## 23. Build sequencing

### 23.1 Phase placement

The Domain tab is **Phase H+** per the project's build plan. It depends on:
- **Phase γ (current):** Management Notebook + Character/Inventory/Party tabs + Unified Log + Henchmen tab + Troops tab
- **Phase H+ prerequisites:** Realtime scheduler monthly cycle implementation; Settlement Panel mercantile flows; Setting generation populating realms; Stronghold construction system (the dependency `gdd-stronghold-construction.md` is its own Phase H+ deliverable)

### 23.2 Build steps

1. Finalize `domains` schema migration per the data model implied by this GDD (identity, territory, population, treasury, realm relationships, morale state, encounter log, departure log entries)
2. Build the Domain tab scene as a child of the management notebook tab strip (`scenes/ui/management_notebook/tabs/domain_tab.tscn`)
3. Implement the entity strip integration (PC + Humanoid Henchman dropdown filter)
4. Implement the Domain Status header per §5
5. Implement the Overview sub-tab per §6 — start here because it's the default landing
6. Implement the Stronghold sub-tab per §7 (consumes stronghold-construction system data)
7. Implement the Garrison sub-tab per §8 (consumes Troops tab data)
8. Implement the Realm sub-tab per §9
9. Implement the Treasury & Ledger sub-tab per §10 (with the project-designed treasury data model)
10. Implement the Decrees & Remote Orders sub-tab per §11 (the small remote-capable activity set; replaces the deprecated centralized Activities picker)
11. Implement the Class-Specific sub-tab matrix per §12
12. Implement the Encounters & Threats sub-tab per §13
13. Implement the Departure Log sub-tab per §14
14. Implement the activity-execution architecture per §15 (location-gating, travel shortcut, future location-panel hooks)
15. Implement empty-state per §19 with class-tailored guidance
16. Implement establish-domain flow (project-designed UI for the conquest / grant / clear paths)
17. Wire monthly-resolution scheduler subscription
18. Wire cross-tab activation entry points per §17
19. Test chaotic-domain branch end-to-end
20. Test pre-9th-level branch end-to-end
21. Test multi-domain navigation end-to-end
22. Test location-gating + travel shortcut for representative activities (administer / research / order_hijink / oversee_troop_training)
23. Visual verification across all nine sub-tabs and the per-class matrix in §12.1

### 23.3 Phase H+ exit criteria for Domain tab

- Domain tab is visible as notebook tab #6 with D-key toggle
- Entity strip filtered to PC + Humanoid Henchman; tab content updates on entity switch
- Status header renders correctly across all nine sub-tabs and all classifications
- All nine sub-tabs render correctly per their specs
- Class-Specific sub-tab visibility matches §12.1 matrix
- Empty-state renders per-class-tailored guidance for entities without a domain
- Establish-domain flow works for civilized (grant + purchase + conquest), borderlands (clear + conquest), wilderness (clear + conquest + clanhold-annex), with class restrictions applied (Explorer, dwarven, elven)
- Chaotic-domain branch works end-to-end (chaotic-aligned PC opt-in at establishment; subsequent mechanics applied)
- Pre-9th-level branch works (no auto-followers, can build/invest/hire)
- Cross-tab activations work per §17
- Activity location-gating works (greyed when wrong location; tooltip; travel shortcut)
- Monthly resolution updates the Domain tab state correctly (revenue, expenses, growth, morale, encounters)
- All citations to RAW are accurate per the rule corpus
- All open questions O-D1 through O-D14 are resolved or confirmed deferred

### 23.4 Dependencies on future GDDs

- **Future Stronghold-Adjacent Panel GDD** (v1.1+ ergonomic shortcut for location-gated activities)
- **Future Magic Research surface GDD** (deeper interaction for arcane casters; may absorb some Magical Research block content)
- **Future Hijink Field-Execution surface GDD** (perpetration UI for syndicate hijinks)
- **Future Vagaries integration GDD** (Vagaries of Recruitment outcome surfacing per O-D12)
- **Future Military Campaign / DaW combat-tactical surface GDD** (tactical resolution; Domain tab feeds and consumes)
- **Future Stronghold Battle-Map surface GDD** (referenced by `gdd-stronghold-construction.md` §11; siege defense at tactical scale)

---

## 24. Revision history

- **v1.7, 2026-05-06** — **Architecture realignment with the real-time-with-pause scheduler GDD.** §11 "Activities sub-tab" rewritten as **§11 "Decrees & Remote Orders sub-tab"** — the prior centralized activity-picker design (with explicit daily-slot quota tracking and an `EventBus.activity_slot_changed` UI counter) conflicted with the canonical real-time-with-pause architecture in `gdd-realtime-scheduler.md` (last updated 2026-04-30). The replacement model is documented in the new `gdd-realtime-scheduler.md` §4.8 "Activity Time Costs and Frequency Semantics": activities carry RAW-derived time costs and execute through the `EventScheduler`; the day's slot quotas (1 major + 2 minor / 8 minor) emerge naturally from a finite ~8-hour active-work budget rather than being enforced as UI constraints; activities launch from their location of execution (settlement panel, stronghold UI, dungeon UI, wilderness commands), not from a centralized picker. The Domain notebook's 6th sub-tab is repurposed to surface only the small set of remote-capable activities (administer_domain, issue_decree, manage_henchmen, conscript_troops, levy_militia, solicit_mercenaries, call_to_arms, oversee_investment) that the ruler can dispatch via seneschal without being physically present at the affected location. **§15.1.1** received a scope clarification: tick-tolerance, daily-tick accumulation, and the abandon-and-resume model apply ONLY to Ongoing-frequency activities — Singular and Restricted activities are atomic and must be restarted from scratch if interrupted. **§3.8 Active Projects** is added on the Character tab (per `gdd-character-tab.md` §3.8) for per-character read-only visibility into running ongoing activities. **§21 Performance considerations** updated to reflect the new sub-tab card counts. **§23 Implementation order** §10 updated to reference the new sub-tab name. No changes to §15.1.2 onward (state model, worked example, departure-warning logic, abandon modal copy) — those mechanics are correct under the new model and apply unchanged to the Ongoing-only scope. Concurrent updates: `gdd-realtime-scheduler.md` §4.8 (new), `gdd-character-tab.md` §3.8 (new), `docs/domain-roadmap-corrected.md` Phase 3 rewrite. Driver: Jedidiah's review of Phase 3 in the corrected domain roadmap, which surfaced the regression risk.
- **v1.6, 2026-04-30** — End-to-end review pass cleaning up stale references and terminology drift accumulated across v1.1-v1.5 successive revisions. **§1 Class-aware UI design intent:** corrected `(§11)` → `(§12)` reference. **§4.2 Sub-tab order:** ambiguous `(§7)` reference clarified to "(strip position 7; full content spec in §12 of this GDD)". **§4.4 Class-Specific visibility:** removed awkward editorial commentary about Wonderworker fighter-progression status; cleaned up to read as a list of multi-bucket-class examples. **§6.1 Growth section:** active-adventuring trigger description aligned with the §6.2 heuristic spec (left-stronghold + at least one of wilderness/dungeon/lair/battle/siege) instead of the generic `EventBus.adventure_started` placeholder. **§7.2 Elven fastness footnote:** stale `§25 Open Questions` reference corrected to point at the cross-doc `gdd-stronghold-construction.md` §13 Q5/Q6 added 2026-04-30. **§11.1 Activities grouping:** Administer Domain moved from Group 1 (Singular) to Group 2 (Ongoing) where it belongs per `ax_campaign_play.xml` §administer_domain (it's a major-ongoing, not a singular). **§11.2 Activity card UI example:** "[Stop ongoing]" button label corrected to "[Abandon activity]" per the v1.2+ terminology sweep. **§12.1 No-checkmarks footnote:** removed stale "(like Bard pending O-D3 resolution)" reference; rewrote to reflect that as of v1.5 every class in the matrix has at least one checkmark, with the no-checkmarks → hidden rule retained as future-proofing. **§15.1.2.1 Worked example table:** corrected Phase 4 to span days 11-14 (4 performing days, ticks reaches 10) and Phase 5 to day 15 (away, absence=5) so the table's end state matches the narrative's `ticks=10, absence=5` figure used in the orc-invasion math. Orc-invasion travel days renumbered 16-20; forfeit on day 21. **§15.1.7 activity card UI examples:** "Absence streak" terminology in the amber and red urgent card examples updated to "Cumulative absence" / "Tolerance remaining" to match the v1.4 cumulative-absence model. The v1.4 sweep had missed these two card examples. **§15.1.7 forfeit cause string:** "absence exceeded tolerance" corrected to "absence exceeded ticks" matching the canonical cause string in §15.1.2 line `EventBus.activity_forfeited`. **§19.1 Bard empty-state:** stale "pending O-D3 confirmation" replaced with the resolved O-D3 disposition pointing the player to the Garrison Training sub-tab. No substantive design changes — all edits were corrections of terminology drift, mis-numbered cross-references, and stale notes left over from previous revisions.
- **v1.5, 2026-04-30** — **All open questions O-D1 through O-D14 resolved per Jedidiah.** Substantive content updates implementing each resolution: **§6.2 Active adventuring detection** rewritten with the explicit two-condition heuristic (left stronghold AND any of wilderness encounter / dungeon-or-lair entry / battle / siege) per O-D1; no manual override. **§10.2 Manual transfers** updated per O-D2 — free if at a domain stronghold, impossible otherwise (treasury is held in stronghold vaults; transfers are physical coin movement). **§11 Activities Group 4 (Senatorial)** removed per O-D7 — senatorial domains out of scope; `consult_senate` is no longer surfaced. **§12.1 Class-bucket matrix** updated for **Bard** (O-D3): Garrison Training ✓ added; Bard-domain-plays-as-Fighter flagged as Arbiter-specific design (Bards lack fighter_progression in RAW). Updated for **Paladin** (O-D4): Faith ✗ removed; only Garrison Training ✓; Paladins are lawful warriors per Roland/Lancelot/El Cid flavor, no magic or divine spellcasting. **§12.6 Garrison Training class list** expanded to include Bard with Arbiter-specific-design flag plus the additional clarifying note. **§12.7 Nobiran Wonderworker aspirant attrition** updated per O-D5 — roll 1d6 each month for 6 months, drop out on 1, not cumulative. **§7.1.1 (new) Non-conforming strongholds** per O-D10 — building blocked, inheriting/conquering allowed, no followers for non-conforming, cross-doc obligation flagged for `gdd-stronghold-construction.md`. **§16.5 Ruler death and succession** rewritten per O-D6 — successor must be appointed within configurable grace period; PC, henchman, or NPC-generator-populated non-henchman; lapse-to-abandonment if no appointment by grace period end; cross-GDD flag for NPC generator. **All §22 open-question entries** marked resolved with strikethrough-and-disposition per project convention; O-D14 deferred-pending-future-combat-tactical-surface GDD with clarifying note.
- **v1.4, 2026-04-30** — **Absence is cumulative for the activity's full lifetime** per Jedidiah. The v1.3 model treated absence as a per-streak counter that reset to 0 on return; v1.4 corrects this to a cumulative counter that never resets while the activity is in progress. Derived clean property: a task can never take more than 2× its base duration in real elapsed time without forfeiting. **§15.1.1** updated with the cumulative-absence emphasis and the 2× max-duration property derivation. **§15.1.2** state model: `absence_streak_days` field renamed to `absence_accumulated`; daily-update logic rewritten — return to location no longer resets absence; the daily check increments either ticks (if performing) or absence (if not performing or absent). **§15.1.2.1 (new)** worked example per Jedidiah's Abel scenario showing cumulative absence behavior across multiple step-aways and culminating in an orc-invasion forfeit choice. **§15.1.4 outcomes** updated: "Return within tolerance" → "Return before forfeit" — absence carries forward rather than resetting on return. **§15.1.5 pre-departure warning** math corrected: tolerance comparison uses remaining tolerance `(ticks - absence)`, not raw ticks; trip projected over remaining tolerance triggers the modal. **§15.1.7 activity card UI** updated to show `Absence: {N} days (cumulative)` and `Tolerance remaining: {ticks - absence}` explicitly so the player always sees the running budget. **§15.3 button states** updated for the cumulative model. Terminology sweep: "absence_streak_days" renamed to "absence_accumulated" throughout; English "absence streak" phrasing replaced with "cumulative absence" or "absence accumulation" to avoid the reset-implication. **O-D17 resolved (v1.4):** present-but-not-performing counts toward absence accumulation per Jedidiah's "same resolution as not being present" — rationale: the tick mechanic measures days of work performed; non-work days at the location are not days of work and consume the same tolerance budget as physical absence.
- **v1.3, 2026-04-30** — **Tick-tolerance mechanic adopted** per official Discord judge consensus (confirmed by Jedidiah), superseding the v1.2 strict-abort model. The new canonical rule: each day an ongoing activity is performed at its required location earns one "tick"; the entity may step away from the activity, but if absence_accumulated exceeds ticks_accumulated the activity is forfeited (progress + gp lost; restart from scratch). Comprehensive §15 rewrite: **§15.1.1 (rewritten)** establishes the tick-tolerance rule with the Discord-quoted definition; **§15.1.2 (new)** defines the per-activity engine state model (`ticks_accumulated`, `absence_accumulated`, daily scheduler boundary update logic); **§15.1.3 (renumbered/refined)** location requirements with the manage_henchmen exception; **§15.1.4 (renumbered)** outcome paths — return within tolerance / exceed tolerance / voluntary abandon / forced departure (no special path; same tick-tolerance applies); **§15.1.5 (new)** pre-departure warning behavior — modal fires only when the engine projects the trip will exceed tolerance, otherwise the player departs freely and the engine tracks the absence; **§15.1.6 (renumbered, copy retained)** abandon-confirmation modal canonical copy unchanged from v1.2 (Jedidiah's specified format); multi-activity variant updated to show tolerance-vs-trip comparison per affected activity; **§15.1.7 (new)** activity-card UI with three visual stages (in-progress on-track / amber-warning absent-within-tolerance / red-urgent absent-near-forfeit); **§15.1.8 (new)** revised player-flow consequence — "configure anywhere, travel to location, execute, optionally step away within tolerance, return and resume — OR abandon and restart." **§15.2 location-gating decision tree** updated for tick-tolerance per category. **§15.3 button states table** rewritten: replaces v1.2's two "in progress" rows with five tick-tolerance states (at-location performing / at-location not-performing / absent within-tolerance / absent near-forfeit / forfeited). **§15.4 / §15.4.1 / §15.4.2** rewritten: §15.4.2 now explicitly notes that v1.2's strict-abort model is superseded, and that bounded pause-and-resume is now the v1 mechanic. Per-class location-gating notes in **§12.2 Faith / §12.3 Magical Research / §12.4 Trade / §12.5 Syndicate / §12.6 Garrison Training** all updated to reference the tick-tolerance rule rather than strict throughout-presence. **O-D15 re-resolved** with the tick-tolerance disposition (bounded pause-and-resume IS now part of v1). **O-D16 resolved** as subsumed by the tick-tolerance rule (no separate involuntary-departure path needed). **O-D17 added (v1.3)** for the present-but-not-performing edge case (default proposal: no absence accumulation while physically at location).
- **v1.2, 2026-04-30** — Strict-RAW behavior locked in per Jedidiah and the canonical abandon-confirmation modal copy specified. **§15.1.4 (new)** establishes the canonical modal copy for any action that would interrupt or terminate an ongoing activity: single-activity variant uses *"WARNING: Taking this action will abandon `<ongoing_task_name>` and forfeit progress, proceed anyway? [Yes, forfeit progress] [No, `<ongoing_task_name>`]"*; multi-activity variant lists each affected activity and uses *"[No, keep activities]"* as the cancel button. Modal is non-bypassable; Enter defaults to safe No; Escape closes-as-No. Optional gp-forfeiture subtitle is informational. **§15.1.2** modal description simplified to defer to §15.1.4 canonical copy. **§15.3** Execute button states for "Already in progress" rows updated to reference §15.1.4. **§15.4.1** travel interrupt-protection updated to use §15.1.4 modal; multi-party scoping clarified (one modal per affected entity, sequenced). **§15.4.2** Pause-and-resume formally **deferred-and-out-of-scope** per Jedidiah — not in v1 or v1.1+; the strict rule is the intentional design. **O-D15** resolved with the no-pause-no-resume disposition. Renamed "abort" terminology to "abandon" throughout the activity-interruption flow to align with the modal's wording.
- **v1.1, 2026-04-30** — RAW-correctness fix per Jedidiah: ongoing activities require **continuous presence at the required location throughout the activity's full duration** per `ax_campaign_play.xml` §frequency_types (*"Ongoing activities require more than one game day and must be performed throughout the listed time period."*). v1 had implied that ongoing activities (research, plan_hijink, consecrate_altar, troop training, etc.) ran autonomously after start, allowing the entity to travel away — that was a misreading. Corrections: **§15.1.1** (new) added explicit statement of the throughout rule with category breakdown (at-structure / in-domain / with-army) and the manage_henchmen exception; **§15.1.2** (new) describes departure-aborts-the-activity behavior with the confirmation modal pattern and the strict no-pause-no-resume v1 rule; **§15.1.3** (new) adds the consequence — travel must precede ongoing activities, with the configure-anywhere → travel-to-location → execute-and-stay-until-complete flow; **§15.2** location-gating decision tree split between singular (presence at execution time only) and ongoing (continuous presence throughout); **§15.3** Execute button state table now includes "Already in progress (entity at correct location)" and "Already in progress (entity has departed location)" rows with explicit forfeiture-of-progress language; **§15.4** travel-shortcut split into pre-execution (§15.4) and during-execution interrupt protection (§15.4.1) with the confirmation modal that lists affected activities and abort consequences; **§15.4.2** (new) defers project-designed pause-and-resume to v1.1+ as O-D15. Per-class block location-gating notes in **§12.2 Faith** (consecrate_altar / consecrate_fields / consecrate_ruler), **§12.3 Magical Research** (research_magic / rewrite_spell / replace_spell / scribe_spell — all four ongoing, all four require continuous sanctum presence), **§12.4 Trade** (solicit_* ongoing variants must remain in market), **§12.5 Syndicate** (plan_hijink / lay_low / perform_hijink continuous presence; await_trial as involuntary location-binding), and **§12.6 Garrison Training** (oversee_troop_training and train_troops both ongoing, both require throughout-presence at training site) all updated to reflect the throughout rule. Added **O-D15** (v1.1+ pause-and-resume mechanic — defaulted to no) and **O-D16** (grace period for involuntary departures — defaulted to zero grace).
- **v1, 2026-04-30** — Initial draft. Specifies Domain tab as notebook tab #6 with per-entity active-entity scope (PCs + Humanoid Henchmen only) per Q1; pre-9th-level support per Q2; personal-domain focus + Realm sub-tab aggregation per Q3; nine sub-tabs (Overview / Stronghold / Garrison / Realm / Treasury & Ledger / Activities / Class-Specific / Encounters & Threats / Departure Log) with §1+§2 merge per Q4; class-conditional Class-Specific sub-tab with stacked-block matrix covering Faith / Magical Research / Trade / Syndicate / Garrison Training buckets; Nobiran Wonderworker hybrid follower rules per Q5 (1d6 cleric/mage 1-3 + 2d6 0th-level INT/WIS≥9 aspirants with 1d6-month dropout); chaotic-domain support from foundation per Q6; class-tailored empty-state acquisition guidance per Q7 with conquest path added per Jedidiah's synthesis correction; hybrid notebook-source-of-truth + greyed location-gating + travel shortcut + future location panels deferred to v1.1+ per Q8. Establishes the Domain Status header (visible across all sub-tabs), per-sub-tab specs, lifecycle interactions (establishment / classification advancement-and-regression / monthly resolution / conquest / abandonment / ruler death and succession / construction completion), cross-tab interactions, multi-party scope, empty-state variants, migration plan (no current Domain UI; Phase H+ build), performance considerations, open questions O-D1 through O-D14, build sequencing with §23.3 Phase H+ exit criteria.


