# ACKS Arbiter — Design Brief v11

**Purpose:** Architectural guide for the build agent. Loaded at the start of every build session. References GDDs for procedural detail and XML rule summaries for ACKS mechanics — does not duplicate them.

**Last updated:** 2026-04-02

---

## 1. What This Is

A sandbox RPG video game that functions as an autonomous Game Master for the Adventurer Conqueror King System (ACKS) First Edition. Single-player at launch; online co-op with shared campaigns is a v2 feature. The app runs the world: applies rules, generates encounters, narrates events, manages NPCs, resolves combat, drives all non-player activity. Players interact through their characters via direct UI controls and free-form text input. No pre-scripted plot, no fixed endgame.

**Governing design principle:** Build mechanically, narrate retroactively. The deterministic rules engine executes all mechanical resolution. An LLM interprets free-form input, makes rules-legal judgments, and narrates results — but never acts outside the engine's action vocabulary. The entire game is testable and functional without any LLM connection.

---

## 2. Technology Stack

- **Engine:** Godot 4, GDScript only
- **Persistence:** SQLite via godot-sqlite GDExtension
- **LLM:** Provider-agnostic service layer supporting cloud APIs (Anthropic, OpenAI, OpenAI-compatible), local models (Ollama, LM Studio, OpenAI-compatible local endpoints), and an offline mock provider. Player configures their provider via an in-game setup wizard.
- **Platform:** Desktop (Windows, macOS, Linux via Godot export)
- **Network:** LLM API calls over HTTPS are the only network requirement; all other features work offline
- **Build orchestration:** OpenClaw agent framework routing tasks to a two-tier model architecture (planning tier: Claude Code with Opus; implementation tier: MiniMax M2.x via Ollama)

**Godot-specific constraints:**
- `class_name` declarations must not appear in autoload scripts (causes "hides an autoload singleton" error)
- godot-sqlite: `query()` returns boolean; results in `db.query_result`; database path uses `"user://"` not `"res://"`
- Banker's rounding (round half to even) is the project-wide rounding standard

---

## 3. Source Material

### 3.1 ACKS Source Books

| Abbreviation | Book | Contents |
|---|---|---|
| ACore | ACKS Core Rulebook | Characters, classes, equipment, proficiencies, spells, adventures, combat, campaigns, monsters, treasure, worldbuilding |
| PC | Player's Companion | Additional classes, class construction (Ch.4 point-budget), supplemental proficiencies/equipment/followers, spell creation procedure |
| HFH | Heroic Fantasy Handbook (excerpted) | Selected heroic classes, proficiencies, races. **Excluded:** HFH class construction mods, shaded/eldritch/ceremonial magic |
| DaW | Domains at War: Campaigns | Armies, military equipment, strategic campaigns, battle resolution, sieges, vagaries |
| LE | Lairs & Encounters | Lair rules, expanded monsters, monster creation, monster parts, training/taming |
| Ax | Axioms Articles (selected) | Errata, new classes, expanded procedures from specific articles |

**Source precedence (highest first):** Axioms → HFH excerpted → APC → L&E → DaW → ACore. Where sources conflict on the same rule, the higher-priority source wins.

### 3.2 Three-Layer Document Architecture

| Layer | Location | Authority | Build Agent May Modify? |
|---|---|---|---|
| **Rules reference library** — XML summaries of ACKS mechanics and tables | `rules/*.xml` | Sacred — extracted from published books | **No.** Implement faithfully. Flag suspected errors. |
| **Generation Design Documents (GDDs)** — project-designed procedures for systems ACKS doesn't cover | `generation/gdd-*.md` | Project-designed | **Yes.** Suggest improvements, fix bugs, refactor. Respect any "ACKS Constraints" sections within. |
| **Design brief** (this document) | `docs/` | Architectural | **Only with approval.** Defines how systems connect. |

The rules reference library is NOT shipped in the final application. It serves as build-time specifications, data source artifacts, and prompt assembly inputs.

### 3.3 Rules Reference Library — Current Files

XML rule summary documents organized by source book and topic:

**ACore:**
`acore_basics_and_characters.xml`, `acore_core_classes.xml`, `acore_campaign_classes.xml`, `acore_demihuman_classes.xml`, `acore_equipment.xml`, `acore_proficiencies_rules_and_catalog.xml`, `acore_spellcaster_rules.xml`, `acore_adventures_and_encounters.xml`, `acore_combat_and_wounds.xml`, `acore-campaign-general-and-magic-research.xml`, `acore-campaign-hijinks.xml`, `acore_axioms_strongholds_and_domains.xml`, `acore-setting-construction-rules.xml`, `acore-monster-stocking-rules.xml`, `acore_treasure_and_magic_items_rules.xml`, `acore_aging_poisons_high-level-start_optional_rules.xml`, `acks_core_spell_catalog_a-i_summary.xml`, `acks_core_spell_catalog_k-w_summary.xml`

Monster catalog (split alphabetically): `acore_monster_catalog_a-dop.xml`, `acore_monster_catalog_drag-gno.xml`, `acore_monster_catalog_dragons.xml`, `acore_monster_catalog_gol-lee.xml`, `acore_monster_catalog_liz-orc.xml`, `acore_monster_catalog_owl-sco.xml`, `acore_monster_catalog_sea-tre.xml`, `acore_monster_catalog_tri-wol.xml`

**APC:**
`pc_classes_1.xml` through `pc_classes_4.xml`, `pc_equipment_catalog.xml`, `pc_proficiencies_catalog.xml`, `pc_followers_tables_rules.xml`, `pc_aging_tables.xml`, `pc_custom_spell_creation_rules.xml`, `pc_magic_experimentation.xml`, `pc_spell_catalog_a-e.xml`, `pc_spell_catalog_f-u.xml`

**DaW:**
`daw_armies_recruitment.xml`, `daw_campaigning_armies.xml`, `daw_campaigns_troop_tables_summary.xml`, `daw_equipment_and_construction.xml`, `daw_sieges.xml`, `daw_vagaries.xml`, `daw_axioms_pitching_battle.xml`

**L&E:**
`le_monster_characteristics_stats.xml`, `le_monster_creation.xml`, `le_monster_parts.xml`, `le_monster_training_rules.xml`, `le_wilderness_lair_rules.xml`

**Axioms:**
`ax_campaign_play.xml`, `ax_codex_and_scroll_magic.xml`, `ax_conditions_catalog.xml`, `ax_domain_level_encounters.xml`, `ax_domains_of_chaos.xml`, `ax_henchmen_recruitment_expanded.xml`, `ax_mortal_wounds_and_tampering.xml`, `ax_reactions_and_influencing.xml`, `ax_thief_skill_update.xml`, `ax_venturer_class.xml`

### 3.4 Generation Design Documents — Current Files

| GDD | System |
|---|---|
| `gdd-setting-generation.md` | 8-layer world generation pipeline (heightmap → climate → politics → demographics → names → infrastructure → LLM narrative → validation) |
| `gdd-terrain-system.md` | Terrain tag system (elevation + biome + water + civilization layers), wilderness hex generation/subdivision, encounter table selection logic, deforestation/forestation; supersedes the earlier `gdd-terrain-wilderness.md` label |
| `gdd-calendar-seasons.md` | Seasonal calendar layer: 4×91-day seasons, solstice/equinox dates, hemisphere inversion, and transition blending |
| `gdd-weather-generation.md` | Deterministic per-hex daily weather, dawn/dusk calculation, climate integration, and DaW weather mapping |
| `gdd-poi-generation.md` | Wilderness point-of-interest taxonomy, placement budgets, mechanical skeletons, and rumor/quest seeding |
| `gdd-dungeon-layout.md` | Procedural dungeon map generation (adapted from donjon, CC BY-NC 3.0), cellular automata caverns, cell-based walls, dual room purpose |
| `gdd-dungeon-factions.md` | Dungeon faction generation, inter-group relationships, territory assignment |
| `gdd-settlement-layout.md` | City/settlement spatial generation (Voronoi blocks, street graphs, districts, vertical layers) |
| `gdd-settlement-stocking.md` | On-demand settlement content generation (buildings, occupants, encounters, commerce, undercity) |
| `gdd-stronghold-construction.md` | Player stronghold planning, grid placement, ACKS construction costs/rules |
| `gdd-trap-generation.md` | Parametric trap generator |
| `gdd-combat-map-generation.md` | Procedural wilderness and urban combat maps on the unified 5' diamond tactical grid |
| `gdd-npc-personality.md` | NPC personality trait system (temperament, motivation, social style, moral compass) |
| `gdd-name-generation.md` | Cultural name tables and phonemic rules |
| `gdd-cultural-religious-generation.md` | Culture and religion generation for settings |
| `gdd-henchman-class-selection.md` | Henchman class selection at level-up |
| `gdd-quest-rumor-system.md` | Rumor generation, quest offer pipelines, reward scaling, and completion tracking |
| `gdd-ui-ux-design.md` | Full UI/UX specification (visual style, screen layouts, interaction patterns, Godot implementation) |
| `gdd-proficiency-specializations.md` | Proficiency specialization enumeration system — closed lists for open-ended proficiencies, trained-creature entity model |
| `gdd_combat_behavior_tags.md` | Eight-family combat AI behavior tag system |
| `gdd-realtime-scheduler.md` | Real-time-with-pause game clock and event scheduler (Draft) — replaces §8.3 day-cycle scheduling and build plan E-2 session runner state machine |

### 3.5 Supporting Architecture Documents — Current Files

| Document | Purpose |
|---|---|
| `document_map.md` | Index of rule summaries, GDDs, system maps, and planning documents |
| `rule_system_map.md` | System-to-file dependency map with upstream/downstream blast-radius guidance |
| `coding_conventions.md` | Naming, file organization, GDScript, SQLite, testing, and cross-subsystem implementation conventions |
| `spell_system_map.md` | Spell-to-system hook map for modifiers, flags, enablers, and effect patterns |
| `proficiency_system_map.md` | Proficiency-to-system hook map for modifiers, flags, enablers, and effect patterns |
| `monster_system_map.md` | Monster stat-block and special-ability hook map across game systems |
| `acks_arbiter_build_plan.md` | Dependency-ordered implementation roadmap and current phase status |

### 3.6 Documents Still Needed

No baseline support documents are currently missing from the architecture manifest. Add new system maps or GDDs only when a new cross-cutting subsystem needs its own dedicated reference.

---

## 4. Build Session Protocol

Every build session that modifies application code:

1. Load this design brief.
2. Load the rule system map, document map, and coding conventions.
3. Load specialized system maps (`spell_system_map.md`, `proficiency_system_map.md`, `monster_system_map.md`) and the build plan when they are relevant to the task.
4. Load only the XML rule summaries and GDDs relevant to the current task.
5. Inspect the current database schema if persistence is involved.
6. Inspect shared data definitions and subsystem boundaries touched by the task.
7. Implement in Godot-native terms: scenes, nodes, resources, autoloads, signals, GDScript classes, SQLite-backed repositories.
8. Register any new actions in the action vocabulary definition file.
9. Run or update focused tests for the affected subsystem and adjacent boundaries.

**Do not load the entire rules corpus.** Each session uses targeted documents identified through the maps.

---

## 5. Spatial Architecture

### 5.1 The Navigation Stack

The game world is a nested spatial hierarchy. The party exists at one level at any time; transitions occur at defined entry/exit points.

| Level | Map Type | Grid Unit | Movement Model | Rules Context |
|---|---|---|---|---|
| Campaign | Hex grid (flat-top) | 24-mile hex | Cell-to-cell | Wilderness (strategic) |
| Regional | Hex grid (flat-top) | 6-mile hex | Cell-to-cell | Wilderness (tactical) |
| Local | Hex grid (flat-top) | 1.5-mile hex | Cell-to-cell | Wilderness / Domain |
| Sea Voyage | Hex grid (flat-top) | 24-mile or 6-mile hex | Cell-to-cell | Sea voyage |
| Settlement (any layer) | Irregular polygon blocks | City block | Node-to-node on street graph | Urban |
| Dungeon / Interior | Diamond grid (isometric) | 5' × 5' cell | Cell-to-cell | Dungeon exploration |
| Battle (temporary) | Diamond grid (isometric) | 5' × 5' cell | Cell-to-cell | Combat |

Hex scales are nested: a 24-mile hex contains 6-mile hexes, which contain 1.5-mile hexes. Settlements have arbitrary vertical layers (surface, upper levels, undercity levels) sharing the same coordinate system. Transition points link all layers.

### 5.2 Transitions

Transitions are prompted at defined transition points:

- Wilderness ↔ Settlement (enter/leave at hex/map edge)
- Wilderness ↔ Dungeon (cave entrance, ruin, etc.)
- Settlement ↔ Dungeon (cellar, sewer, catacombs)
- Settlement ↔ Settlement vertical layers (stairs, grates, lifts)
- Dungeon ↔ Dungeon levels (stairs, shafts, slides)
- Any context → Battle (combat triggers; dungeon/interior maps used directly; wilderness/city generate temporary battle maps per §6.4)
- Wilderness/Settlement ↔ Sea Voyage (board/disembark vessel)

Rules context is an entity-level property, not a global game state. Multiple entities can operate in different contexts simultaneously (e.g., one party in a dungeon while another travels the overworld). Context transitions occur when an entity moves between spatial layers. See `gdd-realtime-scheduler.md` §2.

### 5.3 Unified Map Data Model

All map types share a common abstract structure: id, name, type, grid config, regions (hexes/blocks/rooms), overlay groups, transition points, party position, fog of war, and entities. Type-specific rendering and movement logic operates on this common model.

---

## 6. Map Types

### 6.1 Hex Maps

Flat-top hexagonal grid. Terrain taxonomy from ACKS encounter tables, represented as layered tags per `gdd-terrain-system.md` (elevation + biome + water + civilization). Party token occupies a hex cell; movement crosses boundaries with terrain-based cost. Fog of war per-hex. Nested zoom supported across scales.

### 6.2 Settlement Maps

Irregular polygon blocks on a street graph. Movement is node-to-node on the street network. Districts group blocks by function. POI markers on block perimeters. Vertical layers for undercity and upper-city structures. Full spec in `gdd-settlement-layout.md`; stocking in `gdd-settlement-stocking.md`.

> **Note (Draft):** The walkable polygon-block spatial model is replaced by a node-graph model per `gdd-realtime-scheduler.md` §4. Settlements become weighted node graphs where nodes = Points of Interest and edges = travel connections with time weights. Settlement generation (districts, PoI placement, demographics) is unchanged; only the spatial representation and movement model changes.

### 6.3 Dungeon / Interior Maps

5' diamond grid (isometric) with cell-based walls. Pre-rendered isometric 2D view. Each party member individually positioned. Light radius via Godot 2D lighting. Near-side wall transparency for occluded areas. Rooms detected by flood-fill from wall model. Full spec in `gdd-dungeon-layout.md`.

### 6.4 Battle Maps

When combat triggers outside a dungeon, a temporary 5' isometric diamond grid battle map is needed.

- **Primary:** Procedural generation based on terrain type (forest → trees/undergrowth; city commercial → buildings/stalls/crates). Does not persist after combat.
- **Secondary:** Pre-keyed battle maps attached to specific locations. Persists as campaign data.

---

## 7. Rules Context System

The event scheduler applies different mechanical rules depending on each entity's current spatial context (see `gdd-realtime-scheduler.md`). Context is entity-level, not a global game state — multiple entities may operate in different contexts simultaneously. The rule sets by context:

- **Wilderness (§8.1):** Movement cost by terrain, daily travel distance, encounter checks per hex, getting-lost checks, foraging, supply consumption, camping/watches, weather, scouting
- **Urban (§8.2):** Movement cost per block, district encounter tables, shopping/hiring/information, law enforcement, district modifiers
- **Dungeon (§8.3):** 10-minute exploration turns, wandering monster checks, light source tracking, exploration action economy, trap detection, environmental hazards
- **Combat (§8.4, universal):** Individual initiative (PCs) / grouped initiative (enemies per organizational unit), attack throws (d20 + mods ≥ target), four combat progression types (fighter/cleric/thief/mage), cleave, action economy, morale checks, conditions subsystem
- **Camp (§8.5):** Watch scheduling, rest recovery, encounter checks during watches
- **Sea Voyage (§8.5b):** Sea movement rules, vessel tracking, weather. Naval combat deferred to post-v1.
- **Hijinks (§8.6):** Criminal enterprise management for thief-types in settlements
- **Mercantile (§8.7):** Arbitrage trading, demand modifiers, cargo transport
- **Magic Research (§8.8):** Spell research, item creation, constructs, experimentation
- **Downtime:** Activity selection per character, calendar advancement, domain resolution on month boundaries

**Territory classification:** ACKS 1e defines three tiers — Civilized, Borderlands, Wilderness. These drive encounter frequency, settlement density, and movement rules. "Wilderness" as a territory classification is distinct from "wilderness exploration" as a movement/rules context.

---

## 8. Session Runner

### 8.1 Core Loop

1. **Present state** — location, surroundings, party status, available actions, narrative description.
2. **Receive player input** — via direct UI controls (map clicks, action buttons, menus) or free-form text input (natural language sent to LLM for interpretation).
3. **Resolve action** — UI input executes directly; text input is interpreted by LLM into engine actions, then validated and executed.
4. **Present new state** — narrate results (template for routine, LLM for complex/dramatic), loop back.

Both input paths resolve into the same engine action vocabulary. The LLM interprets and selects; the engine validates and executes.

> **Scheduler note (Draft):** The core loop is now driven by the EventScheduler priority queue rather than a step-by-step state machine. The clock advances to the next scheduled event, the event resolves, and the loop repeats. Player input occurs while the clock is paused. See `gdd-realtime-scheduler.md` §2.

### 8.2 Session States

Major states: Wilderness Exploration, Urban Exploration, Dungeon Exploration, Encounter (uncertain disposition), Combat, Camp/Rest, Downtime, Domain Management, Sea Voyage. Each state has its own loop, action set, and UI layout. Transitions between states are defined in §5.2 and the UI spec in `gdd-ui-ux-design.md`.

> **Scheduler note (Draft):** The states listed above are now entity-level contexts, not global game states. The session runner itself has three states: CAMPAIGN_SELECT, SESSION_ACTIVE (running the event scheduler), and SESSION_END. An entity's context (wilderness, dungeon, urban, combat, etc.) is a property of that entity. Multiple entities can be in different contexts simultaneously. See `gdd-realtime-scheduler.md` §8.

### 8.3 Timekeeping

The game tracks time at multiple granularities: combat rounds (10 seconds), exploration turns (10 minutes), wilderness travel turns (hours), and campaign days/months.
IMPORTANT: The game is to run on a in-game calendar of 13 months with 28 days each, exactly. Otherwise, weeks are 7 days, a dayis 24 hours, an hours is 60 minutes, etc. as normal.

Dawn and dusk times are provided per-hex per-day by the weather system (`gdd-weather-generation.md` §6), which derives them from hex latitude and calendar day. Season definitions are in `gdd-calendar-seasons.md`.

**Clock-driven scheduling (multi-party):** The game clock advances continuously via the EventScheduler. Each entity's orders are scheduled events in a priority queue; the clock advances to the next event and resolves it. Split parties advance independently on the shared clock. Cross-party interactions resolve naturally when entities share a spatial location at the same timestamp. See `gdd-realtime-scheduler.md` §2–3. *(Replaces the previous simultaneous-declaration day-cycle model.)*

### 8.4 Dice System

Toggleable modes: Digital (app rolls and animates), Physical (app prompts, player enters result), Hybrid (default digital, any roll switchable to physical). All rolls logged with full detail: die type, raw result, every modifier with source, final result, outcome.

### 8.5 Override System

Human override allows: editing dice results, editing encounter results, overriding movement, editing world state (HP, inventory, conditions, dispositions), injecting narrative, pausing automation. All overrides logged and marked in the session record.

### 8.6 Henchman Control Model

Henchmen are mechanically directed by the hiring player (combat, movement, exploration) but narratively voiced by the app (dialogue, reactions, opinions). The app enforces loyalty checks on orders that cross tolerance thresholds (suicidal orders, broken promises, unpaid wages, mistreatment). See §10.5 for full lifecycle.

---

## 9. LLM Integration

### 9.1 Action Vocabulary

The engine exposes typed actions (attack, move, cast spell, etc.) that grow as systems are built. Each action specifies: type identifier, parameters, preconditions, effects, and context tags. The vocabulary is stored in a definition file referenced by LLM system prompts. Every LLM-returned action is validated before execution. Unknown, malformed, or rule-violating actions are rejected.

### 9.2 Narration Tiers

| Tier | Mechanism | Use Case |
|---|---|---|
| **Tier 0** | Token-substituted templates | Routine narration (movement, attack results, supply updates) |
| **Tier 1** | Cached LLM generation | First-visit descriptions, loot descriptions, new creature types. Generated once, stored, re-served on return with Tier 0 contextual modifications. |
| **Tier 1.5** | Batch pre-generation | Pre-generate Tier 1 content for likely-next locations during idle time |
| **Tier 2** | Live LLM call | NPC conversations, uncertain encounters, complex narrative moments, boss tactical AI, information gathering |

### 9.3 LLM Service

All LLM calls pass through a central service handling: model selection by task type, API auth, response parsing, retry logic, token usage tracking. The game never calls an LLM API directly.

**Provider types (v1 must support all three):**

- **Cloud API provider** — the player enters an API key for a cloud service (Anthropic, OpenAI, or any OpenAI-compatible endpoint). The LLM Service sends requests over HTTPS. The player pays the cloud provider directly per their API pricing.
- **Local model provider** — the player connects to a locally running model server (Ollama, LM Studio, or any OpenAI-compatible local endpoint). The LLM Service sends requests to `localhost` or a user-configured LAN address. No API key required; inference runs on the player's own hardware at zero per-token cost.
- **Mock provider** — deterministic pattern-matching and template responses for testing and LLM-free play. Activated via a settings toggle ("Offline Mode").

All three provider types return responses in the same format. The game engine, session runner, and UI are completely insulated from which provider is active. Provider selection is config-driven, not code-driven.

**Multi-model strategy:** Different tasks route to different models via a configuration map. Three user-facing quality tiers (Economy / Standard / Premium) adjust model selection across task types. Advanced users can override per task type.

**Cost monitoring:** The app tracks token usage and estimated cost per session, broken down by task type. Displayed in a session summary and accessible in settings. Local model usage shows token counts but zero cost.

### 9.3.1 LLM Setup Wizard (Settings)

The game settings include an **LLM Provider Setup Wizard** that guides the player through connecting their LLM. This wizard runs on first launch and is accessible any time from the Settings screen.

**Wizard flow:**

1. **Choose provider type:** Cloud API / Local Model / Offline (no LLM).
2. **If Cloud API:**
   - Select provider (Anthropic, OpenAI, or Custom OpenAI-compatible endpoint)
   - Enter API key (masked input field)
   - Optionally enter a custom base URL (for proxies or alternative endpoints)
   - Test connection (sends a minimal request, confirms the key works, reports the model list available)
   - Select default model from the available list
   - Select quality tier (Economy / Standard / Premium) which auto-configures the task-to-model routing map
3. **If Local Model:**
   - Enter the local endpoint URL (default: `http://localhost:11434` for Ollama)
   - Test connection (queries the endpoint for available models)
   - Select default model from the detected list
   - Configure context window size (auto-detected if the endpoint reports it, manual override available)
   - Quality tier selection works the same way but routes all tasks to the local model (tier selection affects prompt complexity and response length budgets rather than model choice)
4. **If Offline:** Activates the mock provider. The game is fully playable with template narration. The player can switch to a cloud or local provider later without losing campaign data.

**Settings screen (persistent access):**

The Settings screen exposes all wizard-configured values for manual editing: provider type, API key, endpoint URL, model selection per task type, quality tier, context window override, and a cost/token usage history panel. A "Re-run Setup Wizard" button resets and restarts the guided flow.

### 9.4 Context Assembly

Each Tier 2 call receives a focused context package assembled from game state. Context budgets by task type (e.g., `interpret_player_input`: 1–2K tokens; `npc_dialogue`: 2–4K; `session_summary`: 4–8K). Context includes: current scene, active entities, relevant history (summarized), party state, mechanical context (reaction rolls, rules constraints), and instructions.

### 9.5 Campaign Memory

- **Session log:** Running record of events, auto-summarized by LLM at session end
- **Entity relationship tracker:** Who the party has met, dispositions, deals/promises/grudges
- **Reputation system:** Scoped entries (per-faction, per-settlement, per-location, per-social-group), checked most-specific-first when assembling NPC interaction context
- **Quest/hook tracker:** Active, completed, known-but-unstarted

### 9.6 LLM-Free Play and Testing

The entire game must work without any LLM API connection. This serves two purposes: (1) it validates engine correctness independently of LLM behavior during development, and (2) it provides a fully playable offline mode for users who choose not to configure an LLM provider. The mock provider pattern-matches common inputs to engine actions, returns scripted or template-based responses, and logs the full context it receives for correctness assertions. The template-only baseline (Tier 0 for all narration) is the first build milestone. A player who selects "Offline" in the LLM Setup Wizard gets this mode — functional gameplay with template narration, upgradeable to LLM-enhanced narration at any time without losing campaign data. See `gdd-ui-ux-design.md` §6.4 for latency handling (all LLM calls async, streaming text display).

---

## 10. Character and Party System

### 10.1 Unified Character Model

One schema covers PCs, henchmen, and NPCs. Key sections: identity, attributes (3d6 generation with race/class modifiers), class/level (progression tables from XML), combat stats (derived from class progression type), proficiencies, saving throws, spells (if caster), equipment (positional inventory with auto-encumbrance), personality (from `gdd-npc-personality.md`), relationships, henchman data (if applicable), aging, and dynamic state (conditions, position, formation).

### 10.2 Three-Tier Persistence

| Tier | Scope | Data | When |
|---|---|---|---|
| **A (full)** | PCs, henchmen, major NPCs | Complete stat block, personality, history | Created at generation, persists always |
| **B (named)** | Named NPCs | Simplified stats, personality summary | Persists while relevant |
| **C (transient)** | Encounter-only NPCs | Minimal stats | Generated on encounter, not persisted unless promoted |

### 10.3 Party Management

Max 8 PCs. Henchmen per PC by CHA. Marching formation (point, front, middle, rear). Shared resource pool. Travel speed set by slowest member. Splitting/regrouping supported with time synchronization via day-cycle scheduling.

### 10.4 Reputation

Scoped reputation entries: character-specific or party-wide, by faction/settlement/location/social-group. Checked most-specific to least-specific when assembling NPC interaction context.

### 10.5 Henchman Lifecycle

Five phases:
1. **Search & Generation** — market-class-based availability, full Tier A character generated before interview
2. **Interview & Hiring** — Tier 2 LLM interaction voicing the candidate from their character data; reaction roll + negotiation
3. **Adventuring** — split control model (player directs mechanics, app voices personality, app enforces loyalty)
4. **Employment & Campaign** — wage tracking, treasure share, morale recovery, directed downtime activities
5. **Departure** — deserting/fired henchmen become persistent NPCs in the world

Full spec: `ax_henchmen_recruitment_expanded.xml` (mechanics), `gdd-npc-personality.md` (personality generation), `gdd-henchman-class-selection.md` (level-up class assignment).

### 10.6 XP and Leveling

Two XP streams: Adventure XP (combat + treasure) and Domain XP (monthly domain income). Level-up sequence: HP roll, attack/save updates, proficiency selection, spell updates if applicable, title change. NPCs run the sequence silently during generation.

### 10.7 Languages

Setting-dependent language registry (per `gdd-cultural-religious-generation.md`). Characters have language lists referencing registry IDs. Compatibility checked on NPC dialogue; written materials tagged with language.

---

## 11. Domain Play

Domain play is integral to ACKS and represents ~50% of gameplay at level 5+.

### 11.1 Domain Data Model

Domain record: owner character ID, location (hex reference), region type (Civilized/Borderlands/Wilderness), hex details, population (urban families, peasant families), morale, garrison, stronghold reference, monthly financials (revenue breakdown + expense breakdown + net income + domain XP), improvement history.

Full construction rules in `gdd-stronghold-construction.md`. Economic and administrative rules in `acore_axioms_strongholds_and_domains.xml` and `ax_campaign_play.xml`.

### 11.2 Monthly Resolution

Each game month: collect revenue, pay expenses, check population growth/loss, process domain events, resolve vassal/liege interactions, update morale. Domain XP awarded from net income.

### 11.3 NPC Domain Simulation

NPC rulers are autonomous agents with behavioral profiles (aggression, expansion drive, economic focus, diplomatic preference, loyalty weight, risk tolerance, faction loyalty) driving a deterministic scoring function over available actions. The LLM converts mechanical events to narrative only when events become player-relevant — not every month for every ruler. Strategy reassessment triggers when player actions significantly change a ruler's situation; the LLM returns structured strategic updates that feed back into the scoring function.

---

## 12. Content Generation Pipeline

All v1 content is procedurally generated or hand-authored for testing. Module import is post-v1.

### 12.1 Generation Scales

| Scale | Pipeline | GDD Reference |
|---|---|---|
| Setting (24-mile hex campaign map) | 8-layer pipeline: heightmap → climate → politics → demographics → names → infrastructure → LLM narrative → validation | `gdd-setting-generation.md` |
| Region (6-mile hex zoom-in) | Hex subdivision, terrain extrapolation, settlement/lair placement, NPC generation, encounter table construction | `gdd-setting-generation.md` §14A.3 |
| Settlement | Layout generation → on-demand stocking on contact | `gdd-settlement-layout.md`, `gdd-settlement-stocking.md` |
| Dungeon | Map generation → ACKS stocking → faction generation → LLM narrative | `gdd-dungeon-layout.md`, `gdd-dungeon-factions.md` |
| Encounter | Terrain/territory-based table construction from weighted ingredients | ACKS encounter tables in XML |

### 12.2 Two-Layer Generation

- **Mechanical layer** (from ACKS rules): Determines *what* is generated — counts, types, quantities. Deterministic given dice rolls. Implement faithfully from XML rule summaries.
- **Narrative layer** (LLM): Determines *how it's described* — names, personalities, histories, descriptions. Culturally contextualized from setting data. The LLM explains what the generator built; it does not decide what to build.

### 12.3 Universal Encounter Data Schema

Every encounter group carries the same structured data regardless of content origin (generated, hand-authored, or future module import): `behavioral_disposition`, `reaction_modifier`, `faction_id`, `faction_relationships`, `behavioral_notes`, `preferred_tactics`, `knowledge`. Per-dungeon faction fields: `factions` list, `faction_relationships`, `wandering_context`. One interface, one code path.

### 12.4 Stock on Contact

Settlements and dungeons stock on contact, not on creation. Major POIs and skeleton data are created up front; detail is generated when the party actually interacts with a location and cached permanently.

### 12.5 Build Phases

**Phase 1 — Hand-authored test content:** A starter campaign (hexes, settlement, dungeon, NPCs, factions) validating the engine and universal schemas. Template-only narration (Tier 0). First build milestone: the complete game loop works with zero LLM and zero procedural generation.

**Phase 2 — Procedural generation:** Build and test each generator independently against the hand-authored reference standard. Layer LLM narrative enhancement on top of proven mechanical generation.

---

## 13. Asset Architecture

### 13.1 Semantic ID Registry

All graphical elements referenced by semantic ID, never by hardcoded path. A layered override registry resolves IDs: campaign overrides (highest) → manual file overrides → base defaults (lowest).

### 13.2 Replacement Paths

- **In-app:** Asset management panel in campaign settings, per-campaign scope
- **Manual:** Organized directory structure, swap files keeping same names, bulk replacement supported

### 13.3 Placeholder Strategy

v1 uses 100% build-agent-generated placeholders. A placeholder generator script produces geometric PNG/SVG for every semantic ID without an existing asset. Visual style: dark fantasy vellum aesthetic (see `gdd-ui-ux-design.md` §1). Placeholders are designed to be replaced, not to compete with professional art.

### 13.4 Visual Style

Dark fantasy vellum. Medieval manuscript metaphor. Muted earthy tones, quill-and-ink typography, weathered parchment textures. Dungeon/combat maps use pre-rendered isometric 2D with Godot 2D lighting. Full spec in `gdd-ui-ux-design.md`.

---

## 14. Homebrew and Custom Content

### 14.1 Scope

v1 supports: custom classes (APC Ch.4 construction wizard + bypass editor), custom races (APC + selected HFH), custom monsters (ACore + L&E creation procedures), and spell research (ACore Ch.7 + APC spell-level determination) within the campaign loop. HFH class construction mods and shaded/eldritch/ceremonial magic are out of scope.

### 14.2 Storage

Layered composition matching the asset registry pattern: base content (read-only) → user homebrew library (per-user) → campaign selections (per-campaign) → campaign-created content (per-campaign). Unified runtime catalog per content type, same schema regardless of origin.

### 14.3 Catalog Composition

Homebrew does not rewrite published tables. Encounter pools, NPC demographics, and market availability are composed at runtime from base + enabled homebrew + campaign content. Mid-campaign homebrew changes apply prospectively; removal produces warnings for active references.

---

## 15. Cross-Subsystem Consistency

### 15.1 Shared Data Definitions

A lightweight reference module defines canonical data shapes used by multiple systems: action payloads, character records, map metadata, encounter descriptors, inventory records, response envelopes, event payloads. Define once, treat as canonical.

### 15.2 Coding Conventions

Signals: past-tense verbs (`combat_started`). DB tables: plural snake_case. GDScript classes/scenes: PascalCase. GDScript files: snake_case. Autoloads: only for truly global systems (`GameState`, `CampaignRepository`, `LLMManager`, `AudioRouter`).

### 15.3 Database Schema as Ground Truth

The SQLite schema is the canonical source for persistent data. New subsystems write migrations and update the schema reference.

### 15.4 Subsystem Registration

Core autoloads declare their responsibilities, signals, and dependencies in a lightweight registry document. Stable access boundaries between subsystems: clear method names, typed payloads, explicit signal contracts.

---

## 16. Implementation Priorities

### 16.1 Tier 1 — Core (Build First)

Engine fundamentals that must work before anything else:

- Hex map rendering (Godot TileMap, flat-top), terrain taxonomy, fog of war
- Dungeon square grid with cell-based walls, room auto-detection
- Settlement map (single-district minimum)
- Navigation stack and transitions (state machine)
- Event scheduler and session runner (real-time-with-pause clock, priority-queue event resolution per `gdd-realtime-scheduler.md`) with all exploration contexts
- Combat loop (initiative, attack throws, cleave, morale, conditions)
- Timekeeping (scheduler-driven clock advancement, turn/round zoom, multi-party sync)
- Dice system (digital/physical/hybrid)
- Roll transparency log
- Character data model, unified generation engine, positional inventory
- Three-tier character persistence with promotion
- Party management (formation, splitting, travel speed)
- Henchman lifecycle (search → interview → adventure → employment → departure)
- XP tracking, level-up workflow, aging system
- Scoped reputation system
- Domain data model, monthly resolution, stronghold construction (`gdd-stronghold-construction.md`)
- Asset registry with semantic ID lookup, placeholder generation
- LLM Service abstraction (cloud API + local model + mock providers), action vocabulary framework
- LLM Setup Wizard in Settings (provider selection, API key entry, local endpoint detection, connection test, quality tier)
- Tier 0 template narration library
- Context assembly framework with logging
- Free-form text input panel
- Hand-authored test campaign content
- Shared types package, coding conventions doc, database schema with migrations
- Override system

### 16.2 Tier 2 — Procedural Generation + LLM (Build Second)

- Setting generation pipeline (`gdd-setting-generation.md`)
- Region zoom-in pipeline
- Dungeon stocking pipeline (mechanical + faction generation)
- Settlement stocking pipeline (`gdd-settlement-stocking.md`)
- Encounter table construction
- Tier 1 cached LLM narration
- Tier 2 live LLM NPC interaction
- Campaign memory / narrative continuity
- Boss encounter tactical AI
- Batch pre-generation (Tier 1.5)
- Procedural battle map generation
- NPC domain simulation (§11.3)
- Homebrew content system (class construction wizard, monster builder, spell research)
- Weather system
- Language system

### 16.3 Explicitly Deferred (Post-v1)

- Online co-op with shared campaigns (v2 — Godot multiplayer stack)
- Module Importer (PDF import of published ACKS adventures)
- Naval combat and sea encounter checks (sea voyage travel/navigation IS in scope)
- Full tactical mass combat (v1 uses abstract resolution)
- HFH class construction modifications, shaded/eldritch/ceremonial magic
- Standalone freeform spell-design tools outside campaign research loop
- Monster taming and training as playable subsystem

---

## 17. Key Constraints and Conventions

- **Banker's rounding** (round half to even) everywhere
- **Four combat progression types:** fighter, cleric, thief, mage (not three; "crusader" is a class, "cleric" is the progression type)
- **"Turn undead"** (not "rebuke undead") per ACKS 1e conventions
- **Three territory classifications:** Civilized, Borderlands, Wilderness (not four; no "Outlands" or "Unsettled")
- **LLM narrates, engine decides:** The LLM is a consultant, not a decision-maker. All mechanical outcomes are deterministic.
- **Engine-first, LLM-second:** Every system works in mock/template mode before LLM integration.
- **Build mechanically, narrate retroactively:** Generate structured data first, then dress it with narrative.
- **Stock on contact:** Generate detail when the player interacts, not when the world is created.
- **Godot-native architecture:** Scenes, nodes, signals, resources, autoloads, SQLite-backed repositories. No external frameworks.
- **The action vocabulary is the API:** Typed, validated, versioned. Define actions when you build the system they belong to, not speculatively.
