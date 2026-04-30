# GDD: Domain Tab

**Document type:** Game Design Document (Project-designed, improvable)
**Authority:** Subordinate to `gdd-management-notebook.md`. Authoritative on the Domain tab's content (Status header, sub-tab structure, per-class sub-tab matrix, activity-execution model, lifecycle interactions). Defers to `gdd-stronghold-construction.md` for stronghold-construction details (the Domain tab consumes that GDD's outputs and surfaces them; it does not redefine construction mechanics). Defers to `gdd-troops-tab.md` for troop unit lifecycle (the Domain tab references troop units assigned to a domain's garrison but does not redefine unit mechanics).
**Status:** Draft v1.2 — pending review
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
- **Class-aware UI (Jedidiah's overarching constraint).** Each class has different domain concerns. The Domain tab respects this in three ways: (1) the empty-state acquisition guidance is tailored to the active entity's class per Q7; (2) the Class-Specific sub-tab (§11) surfaces only the high-level activities and resources relevant to the active entity's class; (3) class-gated activities elsewhere in the tab are suppressed or disabled when the active entity's class lacks the relevant capability (e.g., a mage's Garrison sub-tab does not surface `oversee_troop_training` since that activity requires fighter-progression-class).
- **Activity-execution hybrid (Q8 resolution).** The Domain tab is the master inspection-and-execution surface. Every class-applicable activity surfaces here with current state, parameters, and history. Activities that require physical presence at a specific structure are *configurable* in the notebook from anywhere but *executable* only when the active entity is at the required location. Greyed-out execute buttons display a tooltip explaining the location requirement and offer a "Plan travel to [location]" shortcut. v1.1+ may add location-context panels (Stronghold-Adjacent Panel, modeled on the existing Settlement Panel) as ergonomic shortcuts; the notebook remains source of truth.
- **Cross-tab clarity, not duplication.** Stronghold construction details live in `gdd-stronghold-construction.md`. Henchman lifecycle lives in `gdd-henchmen-tab.md`. Troop unit lifecycle lives in `gdd-troops-tab.md`. Settlement-tied activities live in the Settlement Panel. The Domain tab presents *summary readouts* of those systems and offers *cross-activation* into them; it does not redefine their mechanics. This matches the established pattern of the other notebook tabs.
- **Source-of-truth deterministic engine.** Per `CLAUDE.md` Core Principle "Build mechanically, narrate retroactively," all domain mechanics are deterministic engine state. The Domain tab is a presentation layer over that state. Monthly resolution rolls (revenue, morale, growth, encounters) are deterministic given seed + state. LLM narration is *additional* — the Unified Log's Narration tab may show prose for domain events, but the mechanical entries (combat, roll, system) are always emitted alongside.

**Non-goals:**

- The Domain tab does NOT redefine any ACKS rule. Every domain-mechanical claim cites a specific XML file in `rules/`. Project-designed elements (sub-tab structure, activity-execution model, empty-state copy, the Nobiran Wonderworker stronghold rules per Q5) are explicitly tagged "Arbiter-specific design" in their respective sections.
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
7. **Class-Specific** (label varies by class — e.g., "Faith" for divine casters, "Magical Research" for arcane casters, "Trade" for venturers, "Syndicate" for thief/assassin/nightblade, "Garrison Training" for fighter-progression classes) — class-conditional content surfacing only the high-level activities that are gated to the active entity's class. A class with multiple applicable buckets (e.g., Bladedancer = divine + fighter-progression; Nobiran Wonderworker = divine + arcane) sees stacked content blocks within this single sub-tab. The sub-tab does NOT appear at all if the active entity's class has no class-specific high-level activities (e.g., a base 0th-level commoner would not see this sub-tab — though commoners do not rule domains).
8. **Encounters & Threats** — domain encounter log per `ax_domain_level_encounters.xml`, dungeon-monster morale impact (per §dungeons), dangerous-borders configuration, bandit alerts (when current morale ≤ −2), siege state when applicable per `daw_sieges.xml`, invasion / occupation / pillage status
9. **Departure Log** — chronological history of the domain's significant events of loss: classification regression, lost holdings, defeats, abandonment, ruler change, conquest by another power. Permanent record analogous to the Henchmen tab Departure Log

### 4.2 Sub-tab order and tab strip

The TabBar is rendered horizontally below the Domain Status header. With nine sub-tabs the strip may be wider than the page area; per `gdd-ui-shared-services.md` standard TabBar behavior, overflow is handled by horizontal scroll or wrap as appropriate.

The Class-Specific sub-tab (§7) renders with its class-specific label inline (e.g., "Faith" / "Magical Research" / "Syndicate"). When the active entity's class has no class-specific sub-tab content, the sub-tab is hidden entirely — the strip renders eight sub-tabs in that case rather than rendering a placeholder.

### 4.3 Default sub-tab on entity activation

On first activation of the Domain tab for a given entity in a session, the Overview sub-tab is shown. On subsequent activations within the session, the last-active sub-tab for that entity is restored from `per_entity_substate`.

### 4.4 Class-Specific sub-tab visibility logic

The Class-Specific sub-tab (§7 in the strip) appears for active entities whose class has at least one applicable bucket from the matrix in §12.1. The buckets are:

- **Faith** — divine casters (Cleric / Bladedancer / Priestess / Shaman / Nobiran Wonderworker)
- **Magical Research** — arcane casters (Mage / Warlock / Witch / Elven Enchanter / Nobiran Wonderworker)
- **Trade** — Venturer
- **Syndicate** — Thief / Assassin / Elven Nightblade
- **Garrison Training** — Fighter-progression classes who unlock `oversee_troop_training` per `ax_campaign_play.xml` §domain (Fighter / Paladin / Anti-Paladin / Vaultguard / Spellsword / Bladedancer / Barbarian / Explorer / Ruinguard / Dwarven Fury — confirmed by fighter_progression tag in each class's `<role_tags>` plus the level 5+ requirement)

A class falling into multiple buckets (Bladedancer = Faith + Garrison Training; Nobiran Wonderworker = Faith + Magical Research; Wonderworker is also a fighter-progression-eligible? No — `pc_classes_5.xml` shows mage_progression for Wonderworker, not fighter-progression) sees stacked content blocks within the single Class-Specific sub-tab. The sub-tab label takes the form *"Class Activities"* generically, OR is dynamically labeled per primary bucket if only one applies (e.g., a pure Mage's tab is labeled "Magical Research"; a Bladedancer's tab is labeled "Class Activities" because it has Faith + Garrison Training stacked).

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
   - Active-adventuring growth (per §active_adventuring_growth — band-based bonus + race modifiers; conditional on the ruler having actively adventured at least once in the prior month, tracked via `EventBus.adventure_started` events scoped to the ruler)
   - Net change with a "net families this month" headline
4. **Land Value section** — per-hex 3d3 land value (per §land_value), with surveying status (assessed via Land Surveying proficiency, settled-and-revealed, or unknown). Includes any active land improvements (25,000gp per +1gp value, max +3, max 9 per §land_improvement) and their fragility status (lost gp from pillaging)
5. **Classification advancement section** — for each next-tier threshold per §classification_advancement, show progress (e.g., "Borderlands → Civilized: every hex at 250 fam max + urban settlement with 20% of total + within 48 miles of friendly city or large town. Currently: 4/6 hexes at max, urban yes, distance qualifies. Need: 2 more hexes at max OR contiguous-expansion-blocked condition."). For wilderness → borderlands and borderlands → civilized advancement
6. **Alignment & religion** — current ruler alignment vs. apparent domain alignment (per §alignment_and_religion). If mismatch, surfaces the −1 or −2 base morale penalty. Religion section shows current dominant religion + tithes status, and any in-progress religious conversion per §new_religion (the −4 first-month / −2 thereafter penalties + Dedicated-or-half-population convergence conditions)
7. **Recent significant events** — last 5 events from this domain's log (revenue collected, morale roll outcome, encounter, vassal-favor, calamity). Click to open Encounters & Threats or Treasury & Ledger as appropriate

### 6.2 Editable elements

The Overview sub-tab supports these in-place edits (project-designed UI affordances over RAW state):

- **Domain name** — pencil-icon edit on the identity card; text input with character-limit validation; persists immediately on Enter or focus-blur
- **Land Value reveal** — when a hex's land value is unknown but a Land Surveying proficiency throw is available (i.e., a character with the proficiency is present in the domain), surface a "Survey hex" button per `ax_campaign_play.xml` §survey activity (1 minor strenuous activity per hex, target 18+ base modifying with cumulative +4 per prior successful search — but Survey requires Land Surveying; the ACKS RAW differentiation is preserved)
- **Tax / liturgy / tithe rate adjustment** — per `ax_campaign_play.xml` §issue_decree, changing tax or liturgy rate is a minor or trivial activity for the ruler in their domain. The Overview sub-tab surfaces the current rates (default 2gp / 1gp / 1gp per family) with +/− steppers to adjust. Each adjustment is logged immediately and consumes the ruler's activity slot for the day; impact appears next monthly resolution per the morale-event modifiers in §monthly_event_modifiers
- **Active adventuring toggle** (project-designed) — automatic detection-of-adventure based on adventure-started events scoped to the ruler. The Overview sub-tab shows "Active this month: yes / no" status. No manual toggle — the system determines it from event history. (Open question O-D1: whether to allow a manual override for edge cases where the engine misses the heuristic.)

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

### 7.2 Class-specific stronghold notes

The Stronghold sub-tab content is structurally identical across classes — every class has *some* structure unlocking at level 9 — but the **type** of structure varies per the matrix in §12.1. The Stronghold sub-tab labels and visuals adapt: a Mage's tab shows a sanctum / tower icon; a Cleric's a fortified church; a Thief's a hideout; etc.

For **Explorer** specifically: the stronghold is a border fort, and per `acore_axioms_strongholds_and_domains.xml` §classification *"Explorers may only build strongholds in borderlands or wilderness domains."* The "Commission new construction" button for an Explorer gates the structure-build flow to borderlands/wilderness territory; civilized territory shows a tooltip explaining the class restriction.

For **Dwarven** classes (Vaultguard / Craftpriest / Delver / Fury): the stronghold is an underground vault. Per `acore_axioms_strongholds_and_domains.xml` §classification *"dwarven vaults may only be built in wilderness areas or civilized/borderlands areas of their own race."* The build flow gates accordingly.

For **Elven** classes (Spellsword / Courtier / Ranger): the stronghold is a fastness which "must blend seamlessly with nature" per `acore_demihuman_classes.xml`. Same wilderness-or-own-race restriction. The fastness archetype's grid placement rules in `gdd-stronghold-construction.md` §3 should reflect this design intent (project-designed UI for archetype constraints — flag for confirmation in §25 Open Questions).

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
6. **Hire mercenaries** — `ax_campaign_play.xml` §hire_mercenaries activity. Cross-activation to the Settlement Panel's HiringPanel (which lives in `gdd-settlement-exploration-ui.md`) per the established cross-surface pattern. Activity slot consumed; vagaries-of-recruitment roll triggered per RAW
7. **Mercenary officer assignments** — per `daw_campaigns_troop_tables_summary.xml`, Lieutenants / Captains / Colonels / Generals are separately-hired specialists. The Garrison sub-tab surfaces officer-to-unit assignments inline so the player can see which units have officers and their rank. Cross-activation to the Troops tab handles officer-management details

### 8.2 Class-conditional content

- **Fighter-progression classes** (Fighter / Paladin / Anti-Paladin / Vaultguard / Spellsword / Bladedancer / Barbarian / Explorer / Ruinguard / Dwarven Fury): an extra "Train troops" sub-section per `ax_campaign_play.xml` §oversee_troop_training. Surfaced as a button: "Oversee training of {Unit}" with the level-5+ + ruling-a-domain gate, +1 permanent morale bonus to overseen troops, veteran-promotion if ruler also trains
- **Cleric / Bladedancer / Priestess / Shaman**: faithful-follower count is highlighted in the composition list with a special "Faithful (no wages)" badge. The +4 morale and complete loyalty per `acore_core_classes.xml` §Cleric `<loyalty_or_morale_rules>` is surfaced inline
- **Dwarven classes**: composition list flags "Dwarven soldiers" status — per `acore_demihuman_classes.xml` §Vaultguard `<loyalty_or_morale_rules>`: *"The character is expected to employ only soldiers of dwarven descent. Members of other races may be hired for non-soldier tasks."* Non-dwarven soldier units show a warning indicator; non-dwarven non-soldier hirelings are fine

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
   - Both transfers are activity-free (project-designed; treated as logistical, not requiring activity slots; flag as O-D2 if review wants this re-examined)
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

## 11. Activities sub-tab

The Activities sub-tab surfaces the **universal** and **proficiency-gated** activities from `ax_campaign_play.xml` `<category name="domain">` that are available to any domain ruler regardless of class. Class-specific activities (Faith / Magical Research / Trade / Syndicate / Garrison Training) live in §12, not here.

### 11.1 Layout

The sub-tab page is a vertical list of activity cards, grouped by frequency type. Each card shows the activity's current state, parameters, and an execute button (greyed-and-tooltip-explained when location-gated and the entity is not in the right location, per Q8 hybrid execution model in §15).

**Group 1 — Singular activities** (perform within a single game day; may repeat with available activity slots):

- **Administer domain** (major ongoing per `ax_campaign_play.xml` §administer_domain) — the foundational activity. Time: 1/2 × [(6-mile hexes) + (vassals reporting) + (6 − market class of largest urban settlement in personal domain)] days. Effect: +1 morale roll bonus + 5% XP bonus that month per the activity rule. Status card displays: time-required calculation breakdown, current administration status (running this month / not).
- **Issue decree** (minor or trivial per `ax_campaign_play.xml` §issue_decree) — opens a sub-flow with options:
  - Change tax rate (current rate displayed; +/- stepper; per-month effect on revenue + morale modifier per §monthly_event_modifiers)
  - Change liturgy rate (default 1gp; +/- stepper; per-month morale roll modifier)
  - Grant a favor to a vassal (cross-references the Realm sub-tab Favors-and-Duties tracker)
  - Demand a duty of a vassal (same; immediate Henchman Loyalty roll if the vassal already has unsafe duties)
  - Free a perpetrator caught committing a crime (project-designed UI hook to the Crime & Punishment system in §12.5 Syndicate; relevant when the ruler chooses to interfere)
  - Order construction of a new stronghold (cross-activate to `gdd-stronghold-construction.md` commission flow)
  - Order agricultural or urban investment (gp input + investment-type selector; flows into next-month revenue + 1d10/1000gp population growth per §investments)
- **Inspect troops** (minor singular; level 5+ with Command proficiency) — per `ax_campaign_play.xml` §inspect_troops — opens a target-selection sub-flow listing units in the active garrison; selected unit gains +1 to first morale roll within one game day. Greyed unless ruler has Command proficiency
- **Hire mercenaries** (minor singular; requires successful solicit) — per `ax_campaign_play.xml` §hire_mercenaries — cross-activates to Settlement Panel HiringPanel for execution

**Group 2 — Ongoing activities** (require multiple days; sustained over time):

- **Conscript troops** (minor ongoing; 1-3 weeks) — per §conscript_troops; max 1 per 10 peasant families. Card displays: current capacity, conscription progress timeline, vagaries-of-recruitment status from the monthly random-events phase
- **Levy militia** (minor ongoing; 1-3 weeks) — per §levy_militia; max 2 per 10 peasant families. Same status display
- **Solicit mercenaries** (minor ongoing; 1-3 time periods by realm size per §solicit_mercenaries) — opens a sub-flow specifying solicitation quantity and target mercenary types; cross-references Settlement Panel for execution
- **Call to arms** (minor ongoing; 1-3 time periods by realm size; ruler of a realm only) — per §call_to_arms; muster vassals for war; arrival schedule per the muster-delay table from §muster_delay
- **Oversee construction** (minor ongoing; 1 day per 500gp of construction; ruler in domain overseeing construction there) — per §oversee_construction; +5% rate, +10% if ruler also supervising. Card displays: current construction projects in domain (cross-referencing Stronghold sub-tab) with "Oversee" buttons per project
- **Supervise construction** (major ongoing; 1 day per 500gp; requires sufficient Engineering or Siege Engineering ranks) — per §supervise_construction. Same per-project display
- **Oversee investment** (minor ongoing; 1 day per 500gp of investment; ruler in domain overseeing investment ordered there) — per §oversee_investment; the investment attracts 1d10+1 new families instead of usual 1d10 per 1000gp. Card lists active investments in domain with "Oversee" buttons
- **Train troops** (major ongoing; sufficient Mannered at Arms ranks + Riding/Weapon Focus where required) — per §train_troops; up to 60 troops; time depends on troop type. Generic to all classes with the proficiency (the **fighter-progression** version with the `oversee_troop_training` activity lives in §12.6 Garrison Training block — that's the class-gated version)
- **Military campaign** (major ongoing; per §military_campaign) — opens campaign-launch sub-flow when ruler has an army. Cross-references future combat-tactical surface for tactical resolution. Domain tab handles the strategic-stance / regional-movement / supply / occupation summary per `daw_campaigning_armies.xml` weekly procedure once the campaign is active

**Group 3 — Henchman delegation:**

- **Manage henchmen** (trivial ongoing per §manage_henchmen) — surfaces the active entity's henchmen and their current activity assignments. Per RAW: *"A character may actively manage up to four henchmen, plus one additional henchman per point of Charisma bonus and/or Leadership proficiency bonus."* Card displays current active-management capacity (current / max), each henchman's current activity assignment, and an "Assign activity" button per henchman that opens a sub-flow letting the player select an activity from the henchman's eligible list. Cross-references the Henchmen tab for henchman-level details

**Group 4 — Senatorial domains:**

- **Consult senate** (major singular; ruler of a senatorial domain) — per §consult_senate; surfaces only when the active entity rules a senatorial-type domain (project-designed: this is determined by the political-entity type set during setting generation per `gdd-setting-generation.md`). After consulting, decrees become trivial activities

### 11.2 Activity card UI (project-designed)

Each activity card uses a consistent layout:

```
+-----------------------------------------------------------+
| ● Administer Domain                          Major (ong.) |
| Time: 7 days  ·  Status: Active this month  ·  +1 morale  |
| [Stop ongoing] [Inspect math]                             |
+-----------------------------------------------------------+
```

- Activity name + frequency tag (Major / Minor / Trivial × Singular / Restricted / Ongoing)
- Time / cost / effect summary line
- Action button(s):
  - **Active execute** when location and gating conditions met
  - **Greyed with tooltip** when location-gated (e.g., "Available when in Eastmarch — Travel: 4 days") with optional travel shortcut
  - **Greyed with tooltip** when proficiency / class / level gated (e.g., "Requires Engineering proficiency")
  - **Greyed with tooltip** when activity-slot exhausted for the day (e.g., "No major activity slots remaining today")
- Inline "Inspect math" button opens a modal showing the full RAW citation + mod-by-mod calculation for the activity's effect numbers (per the project's transparency principle from `CLAUDE.md` Core Principles)

### 11.3 Daily activity-slot tracking

The Activities sub-tab respects the daily activity capacity per `ax_campaign_play.xml` §daily_capacity: 1 major + 2 minor, OR up to 8 minor, plus unlimited trivial. Strenuous-activity-rest tracking per §effort_rules (rest required after 6 days of strenuous activity) is surfaced with a small status bar at the top of the sub-tab showing the active entity's current daily-slot consumption and overtime-stress (if any).

This shared state is consumed by all activity-execution surfaces — the Activities sub-tab, the Class-Specific sub-tab, and (when implemented) future location panels. Project-designed: the engine's activity-tracking subsystem owns this state and emits `EventBus.activity_slot_changed` for UI refresh.

### 11.4 Activities sub-tab and pre-9th-level entities

A pre-9th-level domain ruler still has access to activities. The activities visible are those whose RAW gating allows pre-9 access (most of them). Activities specifically gated to higher levels (e.g., consecrate ruler at level 9+ in Faith block; manage assistant at level 9+ in Magical Research block) appear greyed with the level requirement noted.

### 11.5 Activities sub-tab empty / no-domain state

For an active entity who does not rule a domain at all, the Activities sub-tab is hidden from the strip — no activities are applicable without a domain. (The other class-conditional sub-tab §12 may still appear if the class has bucket-applicable activities that work outside a domain, e.g., a mage's research activities that can be performed in a borrowed sanctum without ruling a domain — those surface in §12.3 Magical Research with the relevant location-gating rather than being suppressed entirely.)

---

## 12. Class-Specific sub-tab (label varies)

The Class-Specific sub-tab is the central location for high-level activities gated to the active entity's class. The sub-tab label adapts dynamically per §4.4 visibility logic.

### 12.1 Class-bucket matrix

The following matrix maps each class to its applicable buckets. A class may apply to multiple buckets, in which case the sub-tab content stacks blocks for each.

| Class | Faith | Magical Research | Trade | Syndicate | Garrison Training | Notes |
|---|:---:|:---:|:---:|:---:|:---:|---|
| Fighter | | | | | ✓ | castle |
| Mage | | ✓ | | | | sanctum |
| Cleric | ✓ | | | | | fortified church |
| Thief | | | | ✓ | | hideout |
| Dwarven Vaultguard | | | | | ✓ | underground vault; dwarven-soldier-only |
| Dwarven Craftpriest | ✓ | | | | | underground vault; cleric-equivalent for divine |
| Elven Spellsword | | ✓ | | | ✓ | fastness; both arcane caster + fighter-progression |
| Elven Nightblade | | ✓ | | ✓ | | hideout; arcane caster + thief skills |
| Assassin | | | | ✓ | | hideout |
| Bard | | | | | | hall — bards are loremasters but do not unlock divine, magical-research, mercantile, or syndicate buckets per the rule corpus surveyed; their stronghold mechanics are normal-domain ruler. **Open question O-D3:** does Bard get a class-specific sub-tab block at all in v1? Default proposal: no — Bards see no §12 sub-tab. Confirm during review. |
| Bladedancer | ✓ | | | | ✓ | temple; divine + fighter-progression |
| Explorer | | | | | ✓ | border fort; fighter-progression; borderlands/wilderness only |
| Anti-Paladin | ✓ | | | | ✓ | dark fortress; chaotic divine + fighter-progression |
| Barbarian | | | | | ✓ | chieftain's hall |
| Dwarven Delver | | | | | ✓ | underground vault; fighter-progression |
| Dwarven Fury | | | | | ✓ | underground vault; fighter-progression |
| Elven Courtier | | ✓ | | | | elven fastness; arcane caster |
| Elven Enchanter | | ✓ | | | | sanctum; arcane caster |
| Elven Ranger | | | | | ✓ | elven fastness; fighter-progression |
| Paladin | ✓ | | | | ✓ | fortress; lawful divine-aligned + fighter-progression. **Open question O-D4:** does Paladin get a Faith block? Paladins per ACKS Player's Companion are lawful warriors with limited divine flavor; whether they unlock the divine activity category in `ax_campaign_play.xml` §divine is unclear from the class XML alone — the class may or may not have divine spellcasting per `pc_classes_4.xml`. Confirm during review |
| Priestess | ✓ | | | | | cloister |
| Shaman | ✓ | | | | | medicine lodge |
| Warlock | | ✓ | | | | coterie |
| Witch | | ✓ | | | | coven |
| Nobiran Wonderworker | ✓ | ✓ | | | | sanctum (per Q5 resolution); divine + arcane (project-designed hybrid follower rules per §12.7) |
| Zaharan Ruinguard | ✓ | | | | ✓ | dark fortress; chaotic divine + fighter-progression |
| Venturer | | | ✓ | | | guildhouse; mercantile-class |

A class with NO checkmarks (like Bard pending O-D3 resolution) does not see the Class-Specific sub-tab at all per §4.4.

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

**Location-gating:** Most divine activities require the caster to be at their consecrated altar / temple / cloister. Singular activities (cast charitable spells, extract divine power, perform_blood_sacrifice, perform_ceremonial_sacrifice, dispatch missionaries) require presence only at execution time. **Ongoing activities require continuous presence per `ax_campaign_play.xml` §frequency_types:**
- Consecrate altar (1 day per 500gp of altar) — caster must remain at altar throughout
- Consecrate fields (1 day per 780 peasants) — caster must remain in domain throughout, moving through fields as needed
- Consecrate ruler (single performance per year, but ongoing in spirit) — at the ruler's location during the consecration

Greyed in notebook elsewhere with travel shortcut per §15.4. Departing the location during an ongoing divine activity terminates the activity and forfeits the divine power expended per §15.1.2.

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

**Location-gating:** All four major magical activities (research_magic, rewrite_spell, replace_spell, scribe_spell) are **ongoing** per `ax_campaign_play.xml` §magical and require the caster to remain at the sanctum (or borrowed sanctum) **throughout** the activity's full duration per §15.1.1. A mage who begins a 30-day research project must remain at the sanctum for those 30 days; departing terminates the research and forfeits the gp committed per §15.1.2. Manage assistant (trivial restricted) accompanies a major magical activity and is consequently bound to the same location as the supervised activity. Greyed in notebook elsewhere with travel shortcut per §15.4.

### 12.4 Trade block (Venturer)

Surfaces the venturer's mercantile mechanics and high-level monopoly:

- **Guildhouse status** — per `ax_venturer_class.xml` §stronghold_and_followers: stronghold-as-guildhouse following hideout rules
- **Apprentices** — 2d6 venturer apprentices + the venturer's hired ruffians; loyalty / morale rules per the venturer class
- **Monopoly status** (level 12+) — per `ax_venturer_class.xml` §monopoly: the venturer earns 1gp/month per urban family in the urban settlement where they hold monopoly. Display monopoly settlements, monthly monopoly revenue, and competing-venturer status (per RAW: only one venturer can earn monopoly revenue per urban family)
- **Mercantile ventures cross-reference** — the Settlement Panel per `gdd-settlement-exploration-ui.md` owns the actual buy/sell, solicit-merchants, persuade-merchants flows. The Trade block surfaces summary status (current trade routes active, cargo loads in transit, shipping contracts open) and cross-activates to the Settlement Panel for execution
- **Caravan / fleet management** — when the venturer operates caravans / vessels, summary status here

**Location-gating:** Most mercantile activities require the venturer to be in an urban settlement (with caravan or ship for shipping/passenger work). Singular activities (buy_sell_*, hire_hirelings, persuade_*, enter_market) require presence only at execution time. **Ongoing activities (solicit_merchants, solicit_passengers, solicit_shipping_contracts — each 1-3 weeks)** require the venturer to remain in the market through the duration per §15.1.1. Departing the market terminates the solicitation per §15.1.2. Greyed in notebook elsewhere with travel shortcut per §15.4.

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

**Location-gating:** Singular activities (order_hijink as singular major when assigning to all members at base, bribe_magistrate, hire_attorney, interplead) require presence only at execution time. **Ongoing activities require continuous presence per §15.1.1:**
- Plan hijink (2d8+3 / 2d6+3 / 2d4+3 days by level) — perpetrator must remain at hideout throughout planning. Departing terminates planning and forfeits days invested
- Lay low (2d8+3 days) — perpetrator must remain at base throughout. Lay-low is itself a "remain inactive at base" activity by definition; departing breaks lay-low and exposes the perpetrator to detection per `ax_campaign_play.xml` §lay_low
- Perform hijink (1 day for plannable; 3d6+10 / 3d4+8 / 2d6+5 days for ongoing types like carousing/disinforming/slandering/spying/treasure_hunting) — perpetrator must remain at the target location throughout. Field-execution UI is the future hijink-execution surface; the Domain tab tracks status only
- Await trial (by crime severity) — perpetrator is in jail throughout (not voluntary; involuntary location-binding)

Crime & Punishment activities at courthouse / settlement (singular for bribe / hire-attorney / interplead). Greyed in notebook elsewhere with travel shortcut per §15.4.

### 12.6 Garrison Training block (fighter-progression classes)

Surfaces the `<category name="domain"><activity name="oversee_troop_training">` activity per `ax_campaign_play.xml`:

- **Training queue** — list of troop units scheduled for training-overseen-by-ruler. Each unit shows training-time-remaining (depends on troop type), the +1 permanent morale bonus pending on completion, and "veteran-promotion" if ruler is also training
- **Activities** —
  - Oversee troop training (minor ongoing; one ongoing minor activity per 60 troops; level 5+; ruling a domain; +1 permanent morale on completion)
  - Train troops (major ongoing; Mannered at Arms ranks required + Riding/Weapon Focus where required; up to 60 troops; same time as oversight)
- **Class-restricted note** — per `ax_campaign_play.xml` §oversee_troop_training: *"Fighter or other character using fighter attack progression, level 5+, who rules a domain."* The block confirms eligibility and shows the gating

**Location-gating:** Both `oversee_troop_training` and `train_troops` are **ongoing** activities per `ax_campaign_play.xml` §domain. The ruler must remain where the troops are physically training (typically the stronghold) **throughout** the full training duration per §15.1.1. Training durations vary by troop type (per `daw_campaigns_troop_tables_summary.xml` and `daw_armies_recruitment.xml`); a multi-month training program requires multi-month presence. Departing aborts the training, forfeits the time invested, and the +1 permanent morale bonus / veteran promotion does not occur per §15.1.2. Greyed in notebook elsewhere with travel shortcut per §15.4.

### 12.7 Nobiran Wonderworker hybrid block (per Q5 resolution)

The Nobiran Wonderworker is a unique class with no `<stronghold_and_followers>` section in `pc_classes_5.xml`. Per Jedidiah's Q5 resolution, the project-designed hybrid is:

- **Stronghold:** sanctum + dungeon (mage-style)
- **Followers:** 1d6 clerics or mages of level 1-3 + 2d6 0th-level normal-man aspirants
- **Aspirant class determination:** each aspirant's INT and WIS scores determine cleric vs. mage path: highest of the two scores wins; mage wins on tie; both INT and WIS must be ≥9 for the aspirant to qualify (aspirants below the threshold do not arrive)
- **Aspirant attrition:** each 0th-level aspirant has a chance per month of giving up and leaving in 1d6 months (specific % unspecified by Jedidiah; project-designed proposal: roll 1d6 each month per active aspirant, on a 1 the aspirant departs that month; track departure in the Departure Log sub-tab. Open question O-D5 to confirm this dropout rate)
- **Class-Specific sub-tab content:** stacks Faith block + Magical Research block, both of which are accessible since Wonderworker has both arcane and divine progression

**Tag:** This is **Arbiter-specific design** — flagged in the GDD because no ACKS sourcebook publishes this rule. The follower mix is project-designed per Jedidiah's design intent for the class.

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
   - Active siege: per `daw_sieges.xml` definitions (blockade / reduction / assault); siege state breakdown — besieging-army composition, defender garrison, current SHP / max SHP, breaches from reduction, supplies remaining, expected resolution timeline
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

- **Classification regression** per `acore_axioms_strongholds_and_domains.xml` §regression: "Domain classification may regress if the circumstances that justified advancement end." Each regression event logs the old/new classification + the cause (e.g., "loss of urban settlement to dissolution per §dissolution: dropped below 75 urban families")
- **Lost holdings** — when territory is lost (conquered by enemy, abandoned by player choice, ceded to lord, granted to vassal who became independent)
- **Defeats** — battles lost where the domain's garrison was destroyed or repulsed; pillage events; sieges lost
- **Stronghold loss** — when a stronghold falls below 0 SHP and collapses, or is voluntarily demolished, or is captured by an enemy
- **Ruler change** — when the active entity dies or transfers domain rule. The Domain tab persists across ruler changes; the new ruler inherits the domain's state, with a Departure Log entry recording the predecessor
- **Vassal loss** — when a vassal henchman dies, defects, declares independence, or is replaced
- **Religious conversion** — when a domain's religion is changed (per §new_religion); records old religion → new religion + the morale-roll-penalty story arc
- **Monster settlement** — when wandering monsters settle in a dungeon and impose ongoing morale penalty
- **Catastrophic events** — utter catastrophe (−4 morale roll) per §calamities; ruler exile; succession war; etc.

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

### 15.1.1 The "performed throughout" rule for ongoing activities

**This is a core RAW rule with major UX implications.** Per `ax_campaign_play.xml` §frequency_types: *"Ongoing activities require more than one game day and must be performed throughout the listed time period. A major ongoing activity represents full-time labor on a complex project or task. A minor ongoing activity represents intermittent daily effort sustained over a lengthy period."*

**This means an ongoing activity does NOT run autonomously once started.** The active entity must remain physically present at the activity's required location for the activity's full duration. A mage who begins research on a 30-day spell project must remain at their sanctum for those 30 days. A thief who begins planning a hijink (2d8+3 days) must remain at their hideout throughout. A cleric consecrating an altar (1 day per 500gp of altar) must remain at the altar throughout. A ruler overseeing construction must remain at the construction site throughout.

**Location requirements during the activity:**
- **At specific structure** (sanctum / altar / hideout / cloister / construction site / where troops are training): the entity must be physically at that structure for the activity's full duration
- **In domain (anywhere)** (consecrate_fields, conscript_troops, levy_militia): the entity must remain somewhere within the domain for the activity's duration; movement within the domain is permitted
- **With the army** (military_campaign): the entity must remain with the army during the campaign

**Trivial ongoing activities** (manage_henchmen) are an exception per RAW — manage_henchmen specifically allows changing assignments "whenever the henchman is accessible physically or magically," so the location requirement is "henchman is reachable" rather than "ruler is at a specific spot." This is a special case and applies only to manage_henchmen and similarly-flagged trivial-ongoing activities. Each per-activity spec in §11 and §12 notes whether the throughout rule applies and at what location.

### 15.1.2 What happens if the entity leaves during an ongoing activity

Per RAW, departing the required location terminates the activity (the activity has not been "performed throughout"). The Domain tab implements this with project-designed UX safeguards:

**Travel attempt while ongoing activity is in progress** — when the player initiates travel (or any other action) that would take the active entity away from a required-location ongoing activity, the engine raises the **abandon-confirmation modal** per the canonical copy in §15.1.4. The player must explicitly choose to abandon and forfeit progress, or cancel the action and continue the activity.

**Forced departure** (e.g., NPC dragging the entity, magical effects, forced narrative events) — the engine aborts the activity automatically and emits a system-category log entry per `gdd-unified-log-panel.md` §12.2: *"Aldric's research on Detect Magic was interrupted by [cause]. Progress lost; 1,500gp expended is not recoverable."*

**Aborted ongoing activity recovery** — partial progress and partial gp expenditure are NOT recoverable per the strict RAW reading (RAW does not describe pause/resume mechanics). The activity must be restarted from scratch if the entity wants to attempt it again. Project-designed: this is the v1 behavior. Open question O-D15 (added in v1.1) flags whether play testing wants a more lenient pause/resume mechanism in v1.1+.

**Activity-card UI during in-progress ongoing activities** — the activity card shows "In progress: {N} days remaining" plus a prominent "Abandon activity" button (clicking the button raises the abandon-confirmation modal per §15.1.4). If the entity is somehow already away from the required location (should not normally happen since travel triggers the modal pre-departure), the card flags the activity as "Interrupted — must return within {N} days or abort" with an explicit return-or-abort prompt.

### 15.1.4 Abandon-confirmation modal (canonical copy)

Any action that would interrupt or terminate an ongoing activity raises a confirmation modal with the following canonical copy. This applies to the player initiating travel that would depart the activity location, the player clicking "Abandon activity" on an activity card, the player attempting another action that would consume slots already committed to the ongoing activity, or any other interrupting action.

**Single-activity case** (one ongoing activity affected):

```
WARNING: Taking this action will abandon <ongoing_task_name>
and forfeit progress, proceed anyway?

  [Yes, forfeit progress]   [No, <ongoing_task_name>]
```

The `<ongoing_task_name>` placeholder is filled with the user-facing display name of the activity (e.g., "Research: Detect Magic", "Plan hijink: Carouse at Aerendel Tavern", "Oversee Construction: Watchtower"). The "No, ..." button label includes the activity name so the player sees explicitly what they're choosing to keep doing.

**Multi-activity case** (more than one ongoing activity affected by the action — e.g., entity has both research AND plan_hijink in progress at a hideout-with-attached-sanctum, and travel would abort both):

```
WARNING: Taking this action will abandon the following
ongoing activities and forfeit progress, proceed anyway?

  • Research: Detect Magic (8 days remaining)
  • Plan hijink: Carouse (4 days remaining)

  [Yes, forfeit progress]   [No, keep activities]
```

The "No" button label uses the generic "keep activities" plural form when more than one is affected.

**Modal behavior:**
- Modal is non-bypassable — it always raises when an interrupting action is attempted, even if the player has a "Suppress confirmations" preference set elsewhere
- Modal is keyboard-accessible: Enter defaults to the safe "No" choice (project-designed default; the destructive "Yes" choice should require deliberate selection); Escape closes the modal as if "No" were chosen
- Project-designed: a small subtitle below the warning may show the gp committed and that will be forfeited if the player chooses Yes (e.g., *"Forfeiting will lose 1,500gp committed to the research"*); this is informational and not part of the canonical copy

**Voice / tone:** the modal uses the imperative "abandon" / "forfeit progress" because RAW does not describe pause-and-resume — choosing Yes is irrevocable, and the language reflects that gravity. Per Jedidiah's design intent, the modal does not mention any pause / resume / save options because none exist in v1.

### 15.1.3 Consequence: travel must precede ongoing activities

The implication for player flow: the player should be at the required location *before* initiating an ongoing activity. The notebook's pre-flight UI for ongoing activities makes this explicit:

- **At the right location:** the activity card's Begin button is active. Player clicks → activity starts immediately. Entity is now committed to staying at the location for the duration.
- **At the wrong location:** the activity card's Begin button is greyed with the standard tooltip. Player clicks the "Plan travel to {location}" link → travels there → on arrival, the Begin button becomes active → player clicks Begin to start the activity.

This is the Q8 hybrid model's flow: configure-anywhere, travel-to-location, execute-and-stay-until-complete.

### 15.2 Location-gating decision tree per activity

For each activity surfaced in the Domain tab, the location requirement is determined by the activity's RAW definition. This GDD's per-activity specs in §11 and §12 declare the location requirement explicitly. The general patterns:

For **singular** activities (single game day; one execution within the day): location must be correct **at execution time**. The entity is free to depart immediately after, since the activity completes within the day.

For **ongoing** activities (multiple days; performed throughout per §15.1.1): location must be correct **at execution time AND continuously throughout the activity's full duration.** Departing terminates the activity per §15.1.2.

**Location categories:**
- **In personal domain (continuous for ongoing):** administer_domain (ongoing), issue_decree (singular), conscript_troops (ongoing), levy_militia (ongoing), oversee_investment (ongoing), oversee_construction (ongoing), supervise_construction (ongoing). For ongoing variants, the ruler must remain somewhere within the personal domain throughout. Movement within the domain is permitted; departing the domain breaks the activity.
- **At specific structure (continuous for ongoing):** research_magic / scribe / rewrite / replace (at sanctum throughout); consecrate_altar (at altar throughout); plan_hijink / order_hijink / lay_low (at hideout throughout); train_troops / oversee_troop_training / inspect_troops (at stronghold where troops are based throughout for ongoing variants; inspect_troops is singular and only requires presence at execution time)
- **At urban settlement (singular only):** hire_mercenaries, buy_sell_*, solicit_* (entity may depart afterward; for ongoing solicit_* variants, must remain in market through duration), persuade_* (cross-references Settlement Panel)
- **In domain (anywhere; continuous for ongoing):** consecrate_fields (cleric must remain in domain during the activity, moving through the fields as needed); military_campaign (with the army throughout)
- **Ruler need not be present (manage_henchmen exception):** manage_henchmen is the only documented trivial-ongoing activity where presence-throughout does NOT apply per RAW — the activity description explicitly allows reassignment "whenever the henchman is accessible physically or magically." Treat this as the canonical exception
- **At target location (not domain; field execution):** perform_hijink (executed at target by the perpetrator — handled by future hijink-execution surface; the perpetrator must be at the target location for the hijink's duration whether 1 day for plannable hijinks or 3d6+10 days for ongoing hijinks)

### 15.3 Execute button states (UI specification)

For each activity-execute button:

| State | Visual | Tooltip | Action on click |
|---|---|---|---|
| **Active** | Standard button styling | Activity description + cost | Execute the activity, decrement activity slots, log the event, update state |
| **Activity-slot exhausted** | Greyed | "No {Major/Minor} activity slots remaining today" | No action |
| **Wrong location** | Greyed with location icon | "Available at {location_name}. Currently in {current_location}. Travel: {n} days." | Optional "Plan travel" link to the travel system |
| **Insufficient gating** | Greyed with class/proficiency icon | "Requires {gating_description}" (e.g., "Requires Engineering proficiency"; "Requires level 5+"; "Requires fighter attack progression") | No action |
| **Insufficient resources** | Greyed with treasury icon | "Insufficient gp ({available} / {required}gp)" or similar resource specifier | No action |
| **Already in progress (entity at correct location)** | Standard styling, "Abandon" label instead of "Begin" | "{N} days remaining. Click to abandon. **Progress and gp committed are forfeited** per `ax_campaign_play.xml` §frequency_types: ongoing activities must be performed throughout." | Raises abandon-confirmation modal per §15.1.4; on Yes, terminates the activity and logs the abandon with cause "voluntary"; on No, dismisses the modal and the activity continues |
| **Already in progress (entity has departed location)** | Warning styling with red alert icon, "Return or Abandon" label | "Activity interrupted — entity is at {current_location} but must be at {required_location} to continue." | Auto-abort fires per §15.1.2 / O-D16 (no grace period in v1); the activity is logged as terminated due to involuntary departure with cause "interrupted" |

### 15.4 Travel shortcut behavior (pre-execution)

This sub-section covers travel **before starting** an ongoing activity. Travel **during** an ongoing activity is a different concern handled by §15.1.2.

When a wrong-location greyed button shows a "Plan travel" link, clicking it:
1. Opens the travel-planning UI (per `gdd-party-tab.md` §6 Travel sub-tab) pre-populated with the destination
2. The player confirms or modifies the travel plan and dispatches the party
3. On arrival at the destination, the same activity button reactivates automatically (state-driven; no manual re-open of the notebook required to refresh — the button uses the entity's current location signal)
4. Optionally, the engine can emit an `EventBus.activity_reachable(activity_id)` notification when an entity arrives at a location that newly enables a previously-greyed activity, surfaced as a HUD toast

This keeps the player flow tight: notebook → see greyed button → click travel → travel → arrive → notebook button is active → execute → **remain at location until activity completes** (per §15.1.1).

### 15.4.1 Travel during in-progress ongoing activity (interrupt protection)

When the player initiates travel and one or more ongoing activities are in progress that would be interrupted by the travel, the engine raises the abandon-confirmation modal per §15.1.4 (the canonical-copy modal). The single-activity or multi-activity variant is selected based on how many activities are affected by the proposed travel.

If the player chooses **No** ("keep activity" / "keep activities"), the entity stays at the location and the travel attempt is cancelled.

If the player chooses **Yes, forfeit progress**, each affected activity is terminated immediately with a system-category log entry per `gdd-unified-log-panel.md`, then travel proceeds normally. Forfeited gp and days are unrecoverable per strict RAW.

If multiple party members are traveling together but only one of them has ongoing activities at the departure location, the modal scopes to that entity's activities. Other party members travel normally without interruption. If multiple party members each have ongoing activities, the engine raises one modal per affected entity (sequenced) so the player decides per-entity rather than batch-aborting.

### 15.4.2 Pause and resume — out of scope per Jedidiah

RAW does not describe a pause-and-resume mechanic for ongoing activities. Per Jedidiah's confirmation in v1.2, **strict abort-on-interrupt per RAW is the desired v1 behavior and is not slated for change in v1.1+ either.** This is a deliberate design choice: ACKS at high levels assumes the "name-tier" character settles down to research, rule, train, consecrate, etc. — the strict rule reinforces that design intent. Players who want to adventure mid-research may save before starting, abort the research, adventure, then return to restart from scratch.

Open question O-D15 is now resolved (no pause/resume in v1 or v1.1+).

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

- **Conquest** — when an enemy successfully takes a domain by force (per `daw_sieges.xml` and `daw_campaigning_armies.xml` §occupation_and_conquest): the domain is removed from the player's holdings, a Departure Log entry is made, the players' Domain tab for that entity falls back to remaining domains or to the empty state if all are lost
- **Abandonment** — voluntarily abandoning a domain: player flow with confirmation modal explaining the consequences (population disperses, stronghold becomes ruined or available for other rulers, treasury liquidated to ruler's wallet). Logged in Departure Log

### 16.5 Ruler death and succession

When a domain-ruling PC dies:
- The domain enters a succession state (project-designed; flag O-D6 for resolution)
- Per `acore_axioms_strongholds_and_domains.xml` §realms_and_vassals, succession is not explicitly defined for player domains. Default proposal: the deceased PC's domain remains "in succession" (no monthly resolution) until the player either:
  - Designates a successor PC or henchman (via in-game succession act) — domain transfers, Departure Log entry made
  - Lets it lapse — domain is abandoned per §16.4

The Domain tab for the deceased PC shows "Domain in succession" status until resolved.

For henchman-vassal death, the vassal's domain similarly enters succession; the player (as overlord) can reassign to another henchman.

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

### 19.1 Active entity does not yet hold a domain (level 9+)

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
- Bard-specific: pending O-D3 confirmation, no class-specific concerns surfaced

For **Nobiran Wonderworker** (sanctum hybrid per Q5):
- Mage paths plus the Wonderworker's hybrid follower note (1d6 cleric/mage 1-3 + 2d6 0th-level aspirants with INT/WIS≥9 path)

For **Zaharan Ruinguard** (dark fortress):
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
- **Activity catalog rendering:** The Activities sub-tab renders ~20 activity cards. Class-Specific stacks 1-2 buckets with ~5-10 cards each. Negligible render cost; no virtualization needed
- **Realm sub-tab vassal table:** virtualize when vassal count > 30; otherwise render directly

The Domain tab should add zero noticeable latency to gameplay outside of monthly resolution. Monthly resolution is itself a known scheduler-tick boundary event with its own performance budget per `gdd-realtime-scheduler.md`.

---

## 22. Open questions

- **O-D1.** Manual-override toggle for "active adventuring" — should the engine allow the player to manually flag the ruler as having actively adventured this month, in case the heuristic-based detection misses an edge case (e.g., an adventure that occurred in a small dungeon close to the stronghold)? **Default proposal:** no manual override in v1; the heuristic-based detection is authoritative. v1.1+ may add an override if play testing surfaces edge cases.
- **O-D2.** Manual transfer between personal wallet and domain treasury — is this activity-free, or should it consume an activity slot (project-designed)? **Default proposal:** activity-free in v1 (treated as logistical). Re-examine if play testing shows abuse (e.g., infinite gp shuffling between domains).
- **O-D3.** Bard class-specific sub-tab — does Bard get any §12 block in v1? **Default proposal:** no — Bards have a hall stronghold per `acore_campaign_classes.xml` but no documented divine / arcane / mercantile / syndicate / fighter-progression bucket per the rule corpus surveyed. Bard-specific concerns (loremaster abilities, bardic music) live in their character sheet, not the Domain tab.
- **O-D4.** Paladin Faith block — does Paladin unlock the divine activity category in `ax_campaign_play.xml` §divine? Paladins per ACKS Player's Companion are lawful warriors with limited divine flavor; the class XML in `pc_classes_4.xml` may or may not declare divine spellcasting. Confirm by checking `pc_classes_4.xml` Paladin's `<role_tags>` and `<capability_tags>` for divine_caster. **Default proposal pending review:** if Paladin has divine_caster tag, surface §12.2 Faith block; if not, no Faith block.
- **O-D5.** Nobiran Wonderworker aspirant dropout rate — Jedidiah specified 1d6-month dropout per aspirant but did not commit a probability. **Default proposal:** roll 1d6 each month per active aspirant; on 1, that aspirant departs that month (~16.7% monthly attrition). Alternative: per-aspirant cumulative monthly chance of leaving (e.g., flat 10%/mo, or scaled by months-since-arrival). Confirm during review.
- **O-D6.** Domain succession on PC death — what happens to a deceased PC's domain? **Default proposal:** domain enters "in succession" state (no monthly resolution) until the player either designates a successor PC/henchman or lets it lapse to abandonment. Refine if needed.
- **O-D7.** Senatorial domain detection — how does the Domain tab know whether the active domain is senatorial (for the §11 consult_senate activity)? **Default proposal:** political-entity type set during setting generation per `gdd-setting-generation.md` carries a `senatorial: bool` flag. Confirm with setting-generation GDD.
- **O-D8.** Tribute-flow direction in the Treasury & Ledger — when an entity is both a vassal (paying tribute up) and a lord (receiving tribute from sub-vassals), the Treasury sub-tab needs clear visual hierarchy. **Default proposal:** tribute-in (from sub-vassals) appears as Revenue category `tribute_in`; tribute-out (to lord) appears as Expense category `tribute_out`. Net tribute is implicit in the headline net-income calculation. Confirm if a more visual breakdown is wanted.
- **O-D9.** Investment-revenue category granularity — agricultural investments produce 1d10 new families per 1000gp per `acore_axioms_strongholds_and_domains.xml` §investments; urban investments produce 1d10 new urban families per 1000gp per §growing_the_settlement. Should the Treasury & Ledger surface these as separate ledger categories or as a single "Investment" category? **Default proposal:** separate (`investment_agriculture` vs `investment_urban`) for clarity. Confirm.
- **O-D10.** Archetype constraints in the Stronghold sub-tab build flow — `gdd-stronghold-construction.md` §3 Archetypes is the authoritative source. The Domain tab pre-fills archetype based on class but does the build-flow restrict to class-only archetypes, or allow cross-class build (e.g., a Mage building a fortress instead of a sanctum)? **Default proposal:** restrict to class-only archetypes in v1 to keep RAW alignment crisp. Cross-class construction is possible per RAW (any class can build any structure if they have the gp), but the *follower attraction* is tied to the class-specific structure type. Confirm during review.
- **O-D11.** Land Surveyor hireling integration — `acore_axioms_strongholds_and_domains.xml` §land_surveyor specifies that land surveyors are 1st-level explorers with the Cartographer template, hired monthly, available in urban settlements. The Domain tab Overview's "Survey hex" button could either (a) require the active entity to have Land Surveying proficiency themselves, or (b) integrate with hiring a land surveyor hireling. **Default proposal:** v1 supports (a) — proficiency on active entity. v1.1+ adds (b) via the hireling system.
- **O-D12.** Vagaries-of-Recruitment integration — `ax_campaign_play.xml` §vagaries_of_recruitment fires when a ruler is recruiting troops. The vagaries system itself is in `daw_vagaries.xml`. The Domain tab should surface vagary outcomes affecting the active domain (e.g., recruiting failure modes). Specific vagary outcomes are out of scope for this GDD; flag for the Vagaries integration GDD when authored.
- **O-D13.** Realm graph rendering — should the Realm sub-tab include a visual hierarchy/tree view of the realm structure (overlord → vassal → sub-vassal) in addition to the flat list? **Default proposal:** flat list in v1; tree view as v1.1+ enhancement.
- **O-D14.** Military Campaign mid-flight handoff — when a `military_campaign` activity is in progress, does the Domain tab continue to show campaign status, or is that the future combat-tactical surface's responsibility? **Default proposal:** Domain tab Activities sub-tab shows campaign status as a pinned card while active; tactical resolution is the future combat-tactical surface; outcomes flow back into Domain tab via Treasury & Ledger and Encounters & Threats.
- **O-D15.** ~~Pause-and-resume mechanic for ongoing activities~~ **Resolved (v1.2):** **No pause-and-resume in v1 or v1.1+.** Per Jedidiah's confirmation: strict abort-on-interrupt per `ax_campaign_play.xml` §frequency_types is the desired behavior. ACKS at high levels assumes the "name-tier" character settles to research / rule / train / consecrate; the strict rule reinforces that design intent. Players who want to adventure mid-research must save before starting, abort the research, adventure, then return to restart from scratch. The abandon-confirmation modal in §15.1.4 makes the consequence visible and unmistakable.
- **O-D16.** (Added v1.1) Grace period for "Already in progress (entity has departed location)" — when an entity departs an ongoing activity location involuntarily (e.g., forced narrative event, hex-boundary scheduler tick artifact), is there a project-designed grace period before the activity auto-aborts? **Default proposal:** zero grace — departure terminates immediately per RAW. The "Return or Abort" button state in §15.3 only appears in pathological edge cases (state-machine race) and the player should be warned but the engine doesn't postpone the abort. Confirm during review.

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
10. Implement the Activities sub-tab per §11 (universal/proficiency-gated activities)
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

- **v1.2, 2026-04-30** — Strict-RAW behavior locked in per Jedidiah and the canonical abandon-confirmation modal copy specified. **§15.1.4 (new)** establishes the canonical modal copy for any action that would interrupt or terminate an ongoing activity: single-activity variant uses *"WARNING: Taking this action will abandon `<ongoing_task_name>` and forfeit progress, proceed anyway? [Yes, forfeit progress] [No, `<ongoing_task_name>`]"*; multi-activity variant lists each affected activity and uses *"[No, keep activities]"* as the cancel button. Modal is non-bypassable; Enter defaults to safe No; Escape closes-as-No. Optional gp-forfeiture subtitle is informational. **§15.1.2** modal description simplified to defer to §15.1.4 canonical copy. **§15.3** Execute button states for "Already in progress" rows updated to reference §15.1.4. **§15.4.1** travel interrupt-protection updated to use §15.1.4 modal; multi-party scoping clarified (one modal per affected entity, sequenced). **§15.4.2** Pause-and-resume formally **deferred-and-out-of-scope** per Jedidiah — not in v1 or v1.1+; the strict rule is the intentional design. **O-D15** resolved with the no-pause-no-resume disposition. Renamed "abort" terminology to "abandon" throughout the activity-interruption flow to align with the modal's wording.
- **v1.1, 2026-04-30** — RAW-correctness fix per Jedidiah: ongoing activities require **continuous presence at the required location throughout the activity's full duration** per `ax_campaign_play.xml` §frequency_types (*"Ongoing activities require more than one game day and must be performed throughout the listed time period."*). v1 had implied that ongoing activities (research, plan_hijink, consecrate_altar, troop training, etc.) ran autonomously after start, allowing the entity to travel away — that was a misreading. Corrections: **§15.1.1** (new) added explicit statement of the throughout rule with category breakdown (at-structure / in-domain / with-army) and the manage_henchmen exception; **§15.1.2** (new) describes departure-aborts-the-activity behavior with the confirmation modal pattern and the strict no-pause-no-resume v1 rule; **§15.1.3** (new) adds the consequence — travel must precede ongoing activities, with the configure-anywhere → travel-to-location → execute-and-stay-until-complete flow; **§15.2** location-gating decision tree split between singular (presence at execution time only) and ongoing (continuous presence throughout); **§15.3** Execute button state table now includes "Already in progress (entity at correct location)" and "Already in progress (entity has departed location)" rows with explicit forfeiture-of-progress language; **§15.4** travel-shortcut split into pre-execution (§15.4) and during-execution interrupt protection (§15.4.1) with the confirmation modal that lists affected activities and abort consequences; **§15.4.2** (new) defers project-designed pause-and-resume to v1.1+ as O-D15. Per-class block location-gating notes in **§12.2 Faith** (consecrate_altar / consecrate_fields / consecrate_ruler), **§12.3 Magical Research** (research_magic / rewrite_spell / replace_spell / scribe_spell — all four ongoing, all four require continuous sanctum presence), **§12.4 Trade** (solicit_* ongoing variants must remain in market), **§12.5 Syndicate** (plan_hijink / lay_low / perform_hijink continuous presence; await_trial as involuntary location-binding), and **§12.6 Garrison Training** (oversee_troop_training and train_troops both ongoing, both require throughout-presence at training site) all updated to reflect the throughout rule. Added **O-D15** (v1.1+ pause-and-resume mechanic — defaulted to no) and **O-D16** (grace period for involuntary departures — defaulted to zero grace).
- **v1, 2026-04-30** — Initial draft. Specifies Domain tab as notebook tab #6 with per-entity active-entity scope (PCs + Humanoid Henchmen only) per Q1; pre-9th-level support per Q2; personal-domain focus + Realm sub-tab aggregation per Q3; nine sub-tabs (Overview / Stronghold / Garrison / Realm / Treasury & Ledger / Activities / Class-Specific / Encounters & Threats / Departure Log) with §1+§2 merge per Q4; class-conditional Class-Specific sub-tab with stacked-block matrix covering Faith / Magical Research / Trade / Syndicate / Garrison Training buckets; Nobiran Wonderworker hybrid follower rules per Q5 (1d6 cleric/mage 1-3 + 2d6 0th-level INT/WIS≥9 aspirants with 1d6-month dropout); chaotic-domain support from foundation per Q6; class-tailored empty-state acquisition guidance per Q7 with conquest path added per Jedidiah's synthesis correction; hybrid notebook-source-of-truth + greyed location-gating + travel shortcut + future location panels deferred to v1.1+ per Q8. Establishes the Domain Status header (visible across all sub-tabs), per-sub-tab specs, lifecycle interactions (establishment / classification advancement-and-regression / monthly resolution / conquest / abandonment / ruler death and succession / construction completion), cross-tab interactions, multi-party scope, empty-state variants, migration plan (no current Domain UI; Phase H+ build), performance considerations, open questions O-D1 through O-D14, build sequencing with §23.3 Phase H+ exit criteria.


