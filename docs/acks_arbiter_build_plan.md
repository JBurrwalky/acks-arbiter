# ACKS Arbiter — System-by-System Build Plan

Ordered by dependency. Each item should be testable before moving to the next. Complexity ratings estimate the planning/execution difficulty for the build agent.

## Complexity Scale

| Rating | Meaning | Model Strategy |
|--------|---------|----------------|
| **1** | Straightforward data extraction or boilerplate. Any capable model could produce this. | Sonnet, no planning phase needed. |
| **2** | Non-trivial but well-patterned. Follows an established project convention with clear inputs and outputs. | Sonnet, no Opus planning needed. |
| **3** | Multiple interacting subsystems, rule-dense, or architecturally significant. Needs careful upfront design. | Opus plans, Sonnet builds. |
| **4** | Highest integration complexity — many cross-system hooks, ambiguous rule interactions, or novel architecture with no prior pattern to follow. | Opus plans AND builds. |

---

## What's Already Built

These items are complete. Listed for dependency reference only.

### Phase A — Project Scaffold ✅
- A-1: Shared types package (9 types), coding conventions, DB schema (migrations 001–006), CampaignRepository autoload. ✅
- A-2: Override system (OverrideManager autoload, OverridePanel UI). ✅

### Phase B — Core Mechanical Primitives ✅
- B-1: Dice system (DiceSystem autoload, 3 modes, 19 roll types, DicePrompt modal, override integration, roll log). ✅
- B-2: Roll transparency log (session-scoped dice_rolls table, export to JSON). ✅
- B-3: Timekeeping (7th autoload, passive clock, multi-party sync, boundary signals, calendar-seasons subsystem with CalendarConstants and CalendarSeasons). ✅

### Phase C — Character Foundation (partial) ✅
- C-1: Character data model (PC/henchman/NPC unified), 25 class JSONs, power catalog (55 powers), ClassRegistry, PowerRegistry, CharacterGenerator, EncumbranceCalculator, AbilityUtils, equipment catalog (6 JSON files, ~250 items). ✅
- C-2: Spell catalog (231 entries), spell list indices, SpellRegistry, RepertoireEngine, CampaignRepository spell CRUD. ✅
- Spell hook infrastructure: ModifierStack, ModifierContainer, EntityFlags, DamageTypes, ConditionCatalog (27 conditions), DamageResistance, ActiveEffectTracker, SpellEffectRegistry (13 template entries), CharacterData runtime extensions. ✅
- C-3
- C-4
- C-5

### Phase D — Spatial Layers (partial) ✅
- D-1
- D-2
- D-3: Hex map rendering (TileMap, flat-top), terrain taxonomy (4-layer tags), fog of war, hex math utilities. ✅
- D-4
- D-5

### Infrastructure ✅
- Proficiency system map (docs/proficiency_system_map.md) — 667 lines, all proficiencies mapped to 16 system sections with hook patterns. ✅
- Test runner: 22 suites, ~270+ tests via tests/test_runner.tscn. ✅

---

## Pre-Build: Clear Test Debt

**⚠ Before building anything new, run test_runner.tscn in Godot 4.6 and fix all failures.** The build log has carried this forward for six sessions. Migrations 005 and 006 may have broken earlier suites. Fix before adding new code.

---

## TIER 1 — CORE ENGINE

### Phase C — Character Foundation (remaining)

---

#### C-2b: Proficiency Catalog and Registry `⏳ NEXT`

**Complexity: 2**

Follows the exact pattern established by the spell catalog session: mapping document → JSON catalog → GDScript registry. The proficiency_system_map.md is done and provides the complete source material. No architectural novelty.

**Deliverables:**
- `data/proficiencies/proficiency_catalog.json` — All proficiencies from ACore + PC + Axioms. Entry schema: proficiency_id, name, type (general/class), is_ranked, max_rank, selections_allowed, description, hook_pattern (modifier/flag/enabler/threshold_gate/entity/income), effects_by_rank (structured effect descriptors per rank), system_targets (which systems this proficiency touches).
- `engine/subsystems/characters/proficiency_registry.gd` (class ProficiencyRegistry, RefCounted) — Loads catalog. API: get_proficiency(), get_proficiencies_by_type(), get_proficiencies_for_system(), is_ranked(), get_effect_at_rank().
- Wire into CharacterGenerator's auto_select_proficiencies() — validate selections, store rank data.
- Test suite: ~15–20 tests.

**Depends on:** C-1 (CharacterGenerator, ClassRegistry), proficiency_system_map.md.
**Blocks:** C-3 (proficiency selection UI needs the registry).

---

#### C-3: Character Creation UI with Starting Equipment Purchasing

**Complexity: 3**

Nine-step interactive flow (ability rolls → class selection → ability trade → HP → proficiencies → spells → equipment shop → portrait → finalize). Each step calls different subsystems. The equipment shop is a self-contained purchasing subsystem with real-time encumbrance/gold tracking. Multiple ACKS rules must be enforced correctly across step transitions (back-navigation invalidates downstream choices). Build prompt: `phase_c3_prompt.md`.

**Deliverables:**
- 10 UI panel scripts in `scenes/ui/character_creation/`.
- EquipmentCatalog class (RefCounted) with format_cost() utility.
- Reusable character_sheet_panel component.
- Equipment catalog list and inventory display components.
- Placeholder portrait PNGs (256×256 geometric shapes) for all 25 classes + 2 generics.
- Test suite: 17 end-to-end tests.

**Depends on:** C-1, C-2, C-2b, spell hook infrastructure, equipment JSON catalog.
**Blocks:** I-1 (integration test needs character creation).

---

#### C-4: Three-Tier Persistence with Promotion

**Complexity: 3**

Three storage tiers for game entities based on narrative importance, not player lifecycle:

| Tier | Scope | Data | When |
|------|-------|------|------|
| **A (full)** | PCs, henchmen, major NPCs | Complete stat block, personality, history | Created at generation, persists always |
| **B (named)** | Named NPCs | Simplified stats, personality summary | Persists while relevant |
| **C (transient)** | Encounter-only NPCs | Minimal stats | Generated on encounter, not persisted unless promoted |

`CampaignRepository.promote_character()` already exists as a method signature. This phase builds the actual tiered data architecture: Tier C entities live in memory only (generated on the fly by CharacterGenerator for random encounters, discarded after the encounter unless promoted); Tier B entities persist to the DB with a reduced column set (no full inventory, no spell repertoire, no power progression — just enough to run a reaction roll, a combat, and a name); Tier A entities get the full CharacterData treatment.

Promotion (C→B, B→A) fills in the missing data: promoting a transient bandit to a named NPC means generating a personality, assigning a name, and persisting the simplified record; promoting a named NPC to full means expanding to a complete stat block with inventory, proficiencies, spells, and powers. Demotion is also possible (a named NPC the party will never see again can be demoted to free DB rows, though this is a low-priority cleanup operation).

Complexity 3 because: the character data model (CharacterData), the generator (CharacterGenerator), and the repository (CampaignRepository) all need to understand tiers. The DB schema may need a tier column and tier-aware queries (don't load 200 transient NPCs when listing party members). The promotion path must generate plausible missing data (e.g., a Tier C bandit promoted to Tier A needs proficiencies and inventory that make sense for a bandit of that level). This is a data architecture problem that touches the character pipeline end-to-end.

**Deliverables:**
- Tier enum (FULL, NAMED, TRANSIENT) on CharacterData with tier-aware from_dict/to_dict.
- Tier-aware CampaignRepository queries (list by tier, load with tier-appropriate column set).
- Promotion engine: C→B generates name + personality + simplified stats; B→A generates full stat block via CharacterGenerator with constraints from existing data.
- Transient entity lifecycle: created in memory, discarded on encounter end unless promote_character() is called.
- DB migration: tier column on characters table (default FULL for backward compatibility with existing data).
- Test suite: ~15 tests (promotion round-trips, tier-filtered queries, transient lifecycle, backward compat).

**Depends on:** C-1 (CharacterData, CharacterGenerator, CampaignRepository), C-2b (proficiency assignment during B→A promotion).
**Blocks:** E-2 (session runner generates transient encounters), G-2 (henchman hiring may promote a Tier B NPC to Tier A).

---

#### C-5: XP Tracking, Level-Up Workflow, Aging System

**Complexity: 3**

XP awards (monster XP, treasure XP, domain income XP), XP adjustment from prime requisites (AbilityUtils.get_xp_adjustment() exists), level-up procedure (HP roll, new proficiency slots, spell slot expansion, attack/save table advancement via ClassRegistry, class power unlocks via PowerRegistry). Aging system: exact age category tables from acore_aging_poisons_high-level-start_optional_rules.xml and pc_aging_tables.xml replace the approximate thresholds in CharacterData.apply_age_change(). Level-up touches many subsystems (class registry, spell registry, proficiency registry, power registry, dice system) and the rule interactions at level boundaries are dense.

**Deliverables:**
- XP award calculator (monster, treasure, shares, adjustments).
- Level-up engine: orchestrates HP roll, save/attack table update, proficiency slot grant, spell slot expansion, power unlock.
- Aging tables (exact ACKS values), age category transitions with ability score modifications.
- EventBus signals: character_leveled_up, age_category_changed.
- DB persistence for XP totals and level.
- Test suite: ~20 tests.

**Depends on:** C-1, C-2 (spell slot expansion), C-2b (proficiency slot grants at level-up).
**Blocks:** E-2 (session runner awards XP), G-2 (henchman XP sharing).

---

### Phase D — Spatial Layers & Navigation (remaining)

---

#### D-1: Asset Registry with Semantic ID Lookup and Placeholder Generation

**Complexity: 2**

Central registry mapping semantic IDs (e.g., terrain.grass, portrait.fighter_01, ui.icon.sword) to file paths. Placeholder generator creates labeled geometric shapes (colored rectangles/circles with text labels) for every asset in the catalog. After this, the hex map renderer refactors to pull from the registry instead of generating programmatic tiles. Well-defined scope, no ambiguous rules.

**Deliverables:**
- AssetRegistry class/autoload with register(), get_path(), has_asset().
- Placeholder generator script (batch-creates all placeholder PNGs).
- Hex map renderer refactor to use registry lookups.
- Asset manifest file (JSON or GDScript const) defining the complete vocabulary.
- Test suite: ~10 tests.

**Depends on:** B-3 (hex map exists to refactor), C-3 (portrait paths need the registry).
**Blocks:** D-4 (dungeon renderer), D-5 (settlement renderer).

---

#### D-2: Navigation Stack and Scene Transitions

**Complexity: 3**

Scene transition state machine: campaign select → world map → settlement → dungeon → combat. Push/pop stack with transition animations. Each screen implements a standardized interface (enter/exit signals, state save/restore hooks). This is pure Godot architecture — no ACKS rules involved — but the design decisions here constrain every future scene and need to be right the first time. The session runner (E-2) sits directly on top of this.

**Deliverables:**
- NavigationStack manager (autoload or scene-tree singleton).
- Scene interface contract (enter/exit/save_state/restore_state).
- Transition animations (fade, slide — placeholder-quality is fine).
- Campaign select screen (list campaigns, new campaign, load campaign).
- Test suite: ~12 tests (push/pop ordering, state preservation round-trip).

**Depends on:** A-1 (CampaignRepository for campaign list).
**Blocks:** E-2 (session runner drives the nav stack), every scene that uses transitions.

---

#### D-4: Dungeon Square Grid with Cell-Based Walls

**Complexity: 3**

5′ diamond isometric grid. Walls as impassable cells, doors as cells with open/closed state (unified cell-based wall model). Room auto-detection from flood-fill of passable cells. Fog of war (room-scoped: entering a room reveals the whole room). Lighting (torch radius, darkvision). Must integrate with the asset registry. The grid math, room detection algorithm, and door-state model are all non-trivial, and this grid is the foundation for all dungeon content.

**Deliverables:**
- DungeonMapData shared type (grid, cells, wall/door state, room registry).
- DungeonMapController (movement, visibility, door interaction).
- DungeonMapRenderer (isometric diamond tiles, wall rendering, fog).
- Room auto-detection algorithm (flood-fill from seed cells).
- Test dungeon JSON file.
- Test suite: ~20 tests (grid math, room detection, door state, fog transitions).

**Renderer notes:**
- use beige/tan for floors, mid-grey for walls, brown for doors, black for fog.
- door state closed should have an `X` icon overlayed on the tile
- door state open should an `O` icon overlayed.
- grid lines should be black and about 8px wide

**Depends on:** D-1 (asset registry for tile lookups).
**Blocks:** E-2 (dungeon exploration loop), F-1 (combat on dungeon grid), L-1 (dungeon stocking).

---

#### D-5: Settlement Map (Single-District Minimum)

**Complexity: 2**

250′×250′ (50×50 cells) urban grid. Building footprints, streets, market squares. Single-district scope for v1 — enough to support the settlement exploration loop (shopping, hiring, rumors, taverns). Follows the same grid and renderer patterns established by D-4, but simpler (no fog of war, no combat grid, just navigable spaces with labeled buildings). The gdd-settlement-layout.md provides the design spec.

**Deliverables:**
- SettlementMapData shared type (grid, building footprints, labeled locations).
- SettlementMapRenderer (isometric diamond tiles, building labels).
- Test settlement JSON file.
- Test suite: ~10 tests.

**Depends on:** D-1 (asset registry), D-4 (shares grid primitives).
**Blocks:** E-2 (settlement exploration loop), G-2 (henchman hiring happens in settlements).

---

### Phase E — Party & Exploration

---

#### E-1: Party Management

**Complexity: 2**

Party data model (formation slots, marching order), party splitting/merging (multi-party timekeeping already built), travel speed calculation (EncumbranceCalculator already computes movement tiers; this adds terrain cost, forced march, mount speed). Proficiency hooks from proficiency_system_map.md §5.1: Endurance (force march extension), Running (+30′ base movement), Navigation (+4 avoid getting lost). Party inventory (shared pool vs. individual carried). Straightforward data model and calculator work — the multi-party time sync in Timekeeping already handles the hard part.

**Deliverables:**
- PartyData shared type (members, formation, marching order, shared inventory).
- Party management UI (add/remove members, set formation, set marching order).
- Travel speed calculator (terrain × encumbrance × mount × proficiency modifiers).
- Getting-lost check (d6 with Navigation modifier).
- Forced march rules (CON check, Endurance proficiency extension).
- EventBus signals: party_formed, party_split, party_merged.
- Test suite: ~15 tests.

**Depends on:** C-1 (CharacterData), C-4 (character tier for party eligibility), B-3 (Timekeeping for multi-party).
**Blocks:** E-2 (session runner orchestrates party).

---

#### E-2: Session Runner State Machine

**Complexity: 4**

This is the backbone of the game. It orchestrates every other system and has been correctly deferred until now. The session runner manages:

- Campaign select → session start (load CampaignRepository, Timekeeping, party state).
- Wilderness exploration loop: hex movement → encounter check (DiceSystem roll vs. terrain threshold from HexTerrainData.encounter_table_weights()) → time advance (Timekeeping) → event resolution → repeat.
- Dungeon exploration loop: room-by-room movement → trap checks → encounter checks → treasure → repeat.
- Settlement exploration loop: location selection → activity (shop, hire, rest, rumor) → time advance → repeat.
- Combat entry/exit (hands off to combat loop in F-1, receives results back).
- Session end → save all state → return to campaign select.

Also wires long-standing TODOs: game_day into dice_system.gd:_log_and_emit(), Timekeeping.load_state() into session startup, ActiveEffectTracker connection to Timekeeping signals for duration tick-down, player_roll() cancellation signal on forced scene change.

Complexity 4 because: it touches every autoload (GameState, CampaignRepository, Timekeeping, DiceSystem, EventBus, OverrideManager), drives the navigation stack, defines the state transitions that every future feature plugs into, and has no prior pattern in the project to follow. Getting the state machine wrong here means retrofitting everything.

**Deliverables:**
- SessionRunner autoload or scene-tree manager.
- State machine: CAMPAIGN_SELECT, SESSION_ACTIVE, WILDERNESS_EXPLORE, DUNGEON_EXPLORE, SETTLEMENT_EXPLORE, COMBAT, SESSION_END.
- Encounter check wiring (hex_entered → DiceSystem → encounter resolution).
- Time advance wiring (movement → Timekeeping.advance_turns/hours).
- ActiveEffectTracker ↔ Timekeeping signal connections.
- Session save/load orchestration.
- Test suite: ~25 tests (state transitions, save/load round-trip, encounter trigger, time advance).

**Depends on:** D-2 (navigation stack), D-3 (hex map), D-4 (dungeon grid), D-5 (settlement map), E-1 (party data).
**Blocks:** F-1 (combat needs session runner to hand off/receive), everything in Tier 2.

---

### Phase F — Combat

---

#### F-0: Monster Catalog and Registry 

**(Complexity: 2)**
Follows the exact pattern of C-2 (spells) and C-2b (proficiencies). The source XML files are extensive — eight acore_monster_catalog_*.xml files plus seven le_monster_catalog_*.xml files — but the extraction is mechanical. REFERENCE doc/monster_system_map.md during this phase.

**Deliverables:** data/monsters/monster_catalog.json (stat blocks for all ACKS 1e monsters), MonsterRegistry class (RefCounted, same pattern as SpellRegistry/ProficiencyRegistry/ClassRegistry), and integration with EncounterData so encounter resolution can instantiate monsters by ID.

---

#### F-1: Combat Loop

**Complexity: 4**

The single largest and most rule-dense build item in Tier 1. The proficiency_system_map.md §1 (all seven subsections: attack modifiers, damage modifiers, AC modifiers, initiative/surprise, combat maneuvers, defensive/survival, spell interaction) and spell_system_map.md §1 define the hook surface area. The core sequence:

1. Initiative (1d6 per side + Combat Reflexes + Fighting Style modifiers).
2. Declaration phase.
3. Movement (engagement rules, Skirmishing withdrawal-without-declaration).
4. Missile fire (Precise Shooting gating, into-melee penalty, Sniping for ranged backstab).
5. Spell phase (interruption rules, Unflappable Casting recovery).
6. Melee (attack throws with full modifier stack from CharacterData.get_effective_attack_throw(), cleave chain on kill, Combat Trickery maneuvers, Weapon Focus natural-20 double damage).
7. Morale check (2d6 vs. morale score + Command/Leadership modifiers).
8. Condition tick (ActiveEffectTracker duration advancement).

Sub-systems: targeting (melee engagement zone, ranged line-of-sight on diamond grid), damage application (CharacterData.apply_damage() exists), mortal wounds (ax_mortal_wounds_and_tampering.xml), retreat/pursuit, the full condition lifecycle, basic monster behavior ai (see below).

Complexity 4 because: every proficiency hook, every spell effect hook, every modifier stack, and every entity flag converges here. The combat sequence has strict ordering rules from the ACKS XML. Edge cases are dense (cleave chains, backstab multipliers, berserk state, casting interruption). This is where the architecture either validates or collapses.

**Deliverables:**
- CombatManager (orchestrates the full round sequence).
- Initiative system (per-side d6, individual modifiers).
- Attack resolution engine (attack throw calculation, hit/miss, critical, cleave).
- Damage resolution (typed damage, resistance/immunity/vulnerability from DamageResistance).
- Morale check system (2d6 vs. morale, triggers, flight behavior).
- Combat maneuver system (7 maneuvers with Combat Trickery modifiers).
- Mortal wounds table and tampering with mortality.
- Retreat/pursuit rules.
- Combat UI (turn order display, action selection, targeting).
- EventBus signals: combat_started, combat_ended, attack_resolved, creature_killed, morale_broken.
- Basic Monster behavior AI.
- Test suite: ~40+ tests.

**Monster Behavior AI**
The combat manager needs to resolve monster turns, which means: select action (attack, special ability, flee), select target (nearest, most wounded, random — simple heuristics), execute via the same attack/damage pipeline PCs use, check morale at triggers (first death, half casualties, leader killed). The gdd_combat_behavior_tags.md already classifies monster behaviors — F-1 implements the basic tags, O-2 implements the advanced ones.

**Depends on:** E-2 (session runner for combat entry/exit), D-4 (dungeon grid for tactical movement), spell hook infrastructure, proficiency registry.
**Blocks:** G-2 (henchman morale in combat), H-1 (domain military), I-1 (integration test needs combat).

**Session breakdowns**
F-1 Combat Loop — 5 sessions, 18 source files + 14 test files

Session 1: Core round loop, initiative, basic melee attack resolution. Party vs monsters can fight to completion.
Session 2: Wire all 14 spell trigger hooks (no-op implementations), ranged attacks with range bands, condition system integration. This is the session that builds the universal spell interface points you requested.
Session 3: Monster AI using behavior tags, morale checks at correct triggers, cleave chains for fighters.
Session 4: Grid-based movement on TacticalMapData, engagement/withdrawal/retreat rules, 7 combat maneuvers, charging.
Session 5: Mortal wounds tables, XP awards, combat end lifecycle, full SessionRunner integration, combat log.
Each session ends with a testing checkpoint. Specific spell implementations are explicitly deferred to future sessions that can work through the spell catalog in small batches using the hook interface built in Session 2.
---

**F-2: Tactical Combat UI — Session Overview**

**Goal:** Replace the auto-advance placeholder with a playable turn-based tactical combat screen where the player moves and attacks on a grid while the monster AI does the same.

**What exists (reuse entirely):**

CombatController — full state machine, waiting_for_pc_action status, submit_pc_action()
TacticalMapData + IsometricGrid — grid, passability, entity positions, LOS
MovementResolver — BFS pathfinding, reachability, adjacency, engagement
ManeuverResolver — all 7 ACKS maneuvers
MonsterAI — spatial target selection, move+attack decisions
DungeonMapRenderer — already draws a tile grid with entities; adapt or inherit for combat

**What needs to be built:**

Component	Description
scenes/ui/combat/combat_map.tscn + combat_map_renderer.gd	Renders TacticalMapData with combatant tokens; highlights reachable cells and valid attack targets on hover/select
scenes/ui/combat/combat_hud.tscn + combat_hud.gd	Initiative strip (turn order), HP bars, action buttons (Move / Attack / Maneuver / Pass / Flee)
scenes/ui/combat/combat_screen.gd (replace placeholder)	Owns the input loop: on waiting_for_pc_action, highlights the active PC, waits for player clicks, calls submit_pc_action(); on monster turns, runs AI and animates
Input modes	SELECT → MOVE_TARGET → ATTACK_TARGET click state machine; right-click to cancel
Combatant tokens	Simple colored circles/sprites with HP label; selected token highlighted
Post-combat overlay	Victory/defeat card showing XP earned, mortal wound results, downed PCs

**Key integration points:**

CombatController.advance() returns {status: "waiting_for_pc_action", combatant_id, available_actions} — screen polls this and routes to player input vs. AI
CombatState.enter() already pushes the combat screen and calls start_auto_advance(); F-2 replaces start_auto_advance() with the interactive loop
No new combat mechanics needed — UI only

**Deferrals for F-2:**

Spell casting UI (F-3 or later)
Fog of war
Animated movement along path
Sound/VFX

---

### Phase G — NPCs, Social & Economy

---

#### G-1: Scoped Reputation System

**Complexity: 2**

Reputation tracked per faction/settlement/domain. Reputation tiers map to reaction roll modifiers. Proficiency hooks from proficiency_system_map.md §3.1: Diplomacy (+2 parley), Intimidation (+2 threat, HD-gated), Mystic Aura (+2 impress, charmed threshold at ≥12), Seduction (+2 attracted creatures), Bargaining (+2 commercial), Bribery (+2 bribe). Straightforward data model and modifier system — the modifier stack infrastructure already exists.

**Deliverables:**
- ReputationData (per-faction/settlement/domain reputation score and tier).
- Reaction roll modifier calculation (reputation tier + proficiency modifiers + CHA modifier).
- Reputation change events and persistence.
- Test suite: ~12 tests.

**Depends on:** A-1 (CampaignRepository for persistence), C-2b (proficiency registry for modifier lookups).
**Blocks:** G-2 (henchman hiring uses reaction rolls modified by reputation).

---

#### G-2: Henchman Lifecycle

**Complexity: 3**

Full lifecycle state machine: search (settlement availability by market class) → interview (reaction roll with CHA + reputation + proficiency modifiers from G-1) → offer (negotiate compensation) → adventure (loyalty checks, morale in combat via F-1, share of XP/treasure) → employment management (pay, equip, level-up as NPCs via C-5) → departure triggers (loyalty failure, employer death, contract end).

CharacterGenerator.generate_henchman() already produces the entity. This phase adds the lifecycle around it: the hiring UI in settlements, the loyalty/morale subsystem, the XP sharing rules, and the departure triggers.

Proficiency hooks: Leadership (+1 max henchman), Command (+2 morale). Axioms henchman recruitment rules (ax_henchmen_recruitment_expanded.xml) expand the base procedure.

**Deliverables:**
- HenchmanLifecycleManager (state machine: searching → interviewing → employed → departed).
- Hiring UI (search results, interview reaction roll, offer negotiation).
- Loyalty system (monthly loyalty checks, event-triggered checks).
- XP sharing calculator (henchman share rules from ACKS).
- Departure event handling.
- Test suite: ~18 tests.

**Depends on:** G-1 (reputation for reaction rolls), F-1 (morale in combat), C-5 (henchman level-up), D-5 (settlement for hiring location).
**Blocks:** H-1 (domain garrison uses henchmen), I-1 (integration test).

---

### Phase H — Domain Layer

---

#### H-1: Domain Data Model, Monthly Resolution, Stronghold Construction

**Complexity: 4**

Domain record (hex location, population, morale, revenue, garrison, improvements), monthly domain turn (revenue calculation, random events from ax_domain_level_encounters.xml, population growth/decline, morale shifts), stronghold construction pipeline (gdd-stronghold-construction.md, costs from daw_equipment_and_construction.xml).

Proficiency hooks from proficiency_system_map.md §6: Leadership (domain morale +1), Command (garrison morale +2), Engineering (construction supervision capacity), Siege Engineering (fieldworks/siege engines), Craft/Art/Profession (income generation by rank), Theology (religious event identification), Military Strategy (mass combat initiative).

Spell hooks from spell_system_map.md: domain-scale ritual effects (Cataclysm, Plague, Undead Legion — hooks only, not full implementation).

Complexity 4 because: the domain system is a simulation layer running on a different timescale (monthly vs. round-by-round), with its own event table, revenue model, population model, and construction pipeline. It cross-references nearly every other system (combat for garrison, economy for revenue, reputation for vassal relations, hex map for territory). The ACKS domain rules are among the most intricate in the system. Axioms domain-level encounters supersede core rules and add significant complexity.

**Deliverables:**
- DomainData shared type (hex, population, morale, revenue, garrison, improvements, stronghold).
- Monthly resolution engine (revenue, events, population, morale).
- Stronghold construction pipeline (design → cost → build time → completion).
- Domain event table (from ax_domain_level_encounters.xml).
- Domain management UI (overview, monthly report, construction queue).
- Ritual spell hooks (interface stubs for Cataclysm, Plague, Undead Legion).
- EventBus signals: domain_month_resolved, stronghold_completed, domain_event_occurred.
- Test suite: ~30 tests.

**Depends on:** E-2 (session runner for monthly tick), G-1 (reputation for vassal relations), G-2 (henchmen for garrison), D-3 (hex map for territory).
**Blocks:** I-1 (integration test needs a domain-eligible location).

---

### Phase I — Integration Test Content

---

#### I-1: Hand-Authored Test Campaign

**Complexity: 3**

The Phase 1 milestone from design brief §12.5: the complete game loop working with zero LLM and zero procedural generation. A hand-built test region exercising every Tier 1 system.

Content scope:
- 6–8 hex map hexes with pre-placed encounter data (varied terrain types).
- 1 settlement with shops (uses equipment catalog), NPC merchants, henchman candidates, tavern with static rumors.
- 1 dungeon (3–5 rooms with hand-placed monsters, traps, treasure, at least one door).
- 1 domain-eligible stronghold location.
- Pre-written NPC dialogue and event text (static strings, no LLM).
- At least 1 combat encounter testing the full combat loop.
- At least 1 henchman hiring sequence.

Complexity 3 because: this isn't a coding task — it's a systems integration verification. Every system from A through H gets exercised together for the first time. The test content must be carefully designed to hit edge cases (e.g., a caster PC, a fighter PC, equipment encumbrance thresholds, a morale check trigger, a domain revenue cycle). Bugs found here require fixes across multiple systems.

**Deliverables:**
- Hand-authored campaign data files (JSON) for all content above.
- Walkthrough script documenting the expected sequence of play.
- Bug list and fix pass.
- Updated test_runner if automated integration tests are feasible.

**Depends on:** Everything in Phases A–H.
**Blocks:** Phase J (LLM layer builds on proven mechanical loop).

---

### Phase J — LLM & Narration Layer

---

#### J-1: LLM Service Abstraction

**Complexity: 3**

LLMManager already exists as a stub returning ResponseEnvelope.fallback(). Replace with real provider architecture: cloud API provider (Anthropic/OpenAI), local model provider (Ollama), mock provider (for testing). Unified request/response interface. Rate limiting, retry logic, token budgeting. Provider-specific request formatting (different APIs have different message formats, token limits, streaming behavior).

Complexity 3 because: the abstraction must be clean enough that every downstream consumer (narration, NPC dialogue, free-form input) uses the same interface regardless of provider. Getting the provider abstraction wrong means rewriting every consumer later. The Ollama local model path has different latency characteristics and failure modes than cloud APIs.

**Deliverables:**
- LLMProvider interface (abstract class or protocol).
- CloudAPIProvider (Anthropic, OpenAI — configurable).
- LocalModelProvider (Ollama auto-discovery, endpoint management).
- MockProvider (deterministic responses for testing).
- LLMManager refactor (provider registry, request routing, rate limiting, retry).
- Token budget tracker.
- Test suite: ~15 tests (mock provider round-trip, rate limiting, fallback on failure).

**Depends on:** A-1 (ResponseEnvelope, GameState for settings).
**Blocks:** J-2 (setup wizard configures providers), J-4 (context assembly sends requests).

---

#### J-2: LLM Setup Wizard in Settings

**Complexity: 2**

Settings UI: provider selection dropdown, API key entry (cloud), local endpoint detection (Ollama auto-discover on localhost ports), connection test button, quality tier selection (Tier 0 template-only / Tier 1 cached / Tier 2 live). Persists to user://settings.cfg (GameState already has this pattern). Straightforward UI form backed by the provider architecture from J-1.

**Deliverables:**
- LLM Settings panel (CanvasLayer, accessible from main menu).
- Provider selection, API key entry, endpoint configuration.
- Connection test (send a simple prompt, verify response).
- Quality tier selector with descriptions.
- Persistence to settings.cfg.
- Test suite: ~8 tests.

**Depends on:** J-1 (provider abstraction to configure).
**Blocks:** J-3, J-4, J-5 (all need a configured provider).

---

#### J-3: Tier 0 Template Narration Library

**Complexity: 1**

Pre-written template strings for all common game events: combat hits/misses ("The [attacker] strikes the [target] for [damage] damage"), treasure found, door opened, NPC greeting, exploration descriptions, etc. Variable substitution for names, numbers, items. This is the fallback when LLM is unavailable or for high-frequency events too trivial for an LLM call. Essentially a big dictionary of string templates with a simple formatter.

**Deliverables:**
- NarrationTemplateLibrary class.
- Template JSON files organized by event category.
- String formatter with variable substitution.
- Test suite: ~10 tests.

**Depends on:** None (standalone utility).
**Blocks:** J-4 (context assembly uses templates as fallback).

---

#### J-4: Context Assembly Framework with Logging

**Complexity: 3**

Builds the LLM prompt from game state: current location (hex terrain, dungeon room, settlement), recent events (last N actions from session log), NPC personality data (from gdd-npc-personality.md schema), party composition, session history, relevant world lore. Token budget enforcement (different providers have different limits; context must fit). Logging for every assembled context (debug and replay — what prompt was sent, what response came back, how many tokens).

Complexity 3 because: context assembly is where "build mechanically, narrate retroactively" is enforced architecturally. The framework must guarantee that the LLM receives only mechanical outputs to narrate and never makes mechanical decisions. The context window management (what to include, what to truncate, priority ordering) is a design-heavy problem.

**Deliverables:**
- ContextAssembler class (builds prompt from game state components).
- Context component registry (location, events, NPCs, party, world — each a pluggable module).
- Token budget manager (per-component allocation, truncation strategy).
- Context log (every assembled prompt + response logged to file).
- Integration with LLMManager request pipeline.
- Test suite: ~15 tests (budget enforcement, component ordering, truncation).

**Depends on:** J-1 (LLMManager for token limits), E-2 (session runner for game state).
**Blocks:** J-5 (free-form input uses context assembly), N-1 (per-entity narration).

---

#### J-5: Free-Form Text Input Panel

**Complexity: 3**

Player types natural language → context assembled (J-4) → LLM processes → action vocabulary mapped → mechanical resolution → LLM narrates result. The action vocabulary framework (coding_conventions §10.1, still PROVISIONAL) gets finalized here: the set of mechanical actions the LLM can invoke, the structured format for action payloads (ActionPayload shared type already exists), and the validation/execution pipeline.

Complexity 3 because: this is the first time the LLM's output drives mechanical actions, which inverts the usual flow. The action vocabulary must be comprehensive enough to cover common player intents but constrained enough that the LLM can't produce invalid mechanical outcomes. Parsing and validating LLM output is inherently fuzzy.

**Deliverables:**
- Free-form text input UI panel (text field, send button, response display).
- Action vocabulary definition (finalize §10.1 — the complete set of actions the LLM can invoke).
- LLM response parser (extract action vocabulary commands from natural language response).
- Action executor (validates parsed actions, dispatches to mechanical systems).
- Fallback handling (LLM returns unparseable response → graceful degradation to template narration).
- Test suite: ~15 tests (action parsing, validation, execution, fallback).

**Depends on:** J-4 (context assembly), J-1 (LLM provider), E-2 (session runner for action execution context).
**Blocks:** Tier 2 LLM narration phases.

---

## TIER 2 — PROCEDURAL GENERATION + LLM NARRATION

### Phase K — Setting Generation Pipeline

---

#### K-1: Terrain System Implementation

**Complexity: 2**

Implements the terrain generation rules from gdd-terrain-system.md on top of the hex map infrastructure. Procedural terrain assignment for regional (6-mile) and campaign (24-mile) hex maps. Elevation, biome, water, and civilization layers (HexTerrainData already defines the 4-layer schema). Köppen climate code assignment per hex.

**Depends on:** D-3 (hex map data model).
**Blocks:** K-2 (setting gen consumes terrain), L-5 (weather needs climate codes).

---

#### K-2: Setting Generation Pipeline, Layers 1–5

**Complexity: 4**

The full procedural setting generator from gdd-setting-generation.md: geography (terrain, rivers, coastlines), demographics (population density by territory classification — Civilized/Borderlands/Wilderness), political entities (realms, vassal hierarchies, borders), culture seeding, religion seeding. Five interdependent generation layers that must produce a coherent, playable campaign map.

Complexity 4 because: this is the most algorithmically complex generation pipeline in the project. Each layer constrains the next. The demographic model (ACKS population density by market class and territory type) is mathematically precise and must match the sacred XML tables. Political entity generation involves graph algorithms (territory partitioning, vassal hierarchy construction). The output must be mechanically valid for the domain system (H-1).

**Depends on:** K-1 (terrain), D-3 (hex map), H-1 (domain model for validity checks).
**Blocks:** K-3 (culture/religion), L-1 through L-5 (all content seeding).

---

#### K-3: Cultural and Religious Generation

**Complexity: 3**

Implements gdd-cultural-religious-generation.md. 1:1 culture-religion seeding model: each culture paired with exactly one religion, culture's primary religion must match its dominant alignment, opposing-alignment religions capped at 15%. Generates cultural traits (naming conventions, social structures, aesthetic preferences) and religious traits (deity names, holy days, clerical restrictions) for LLM narration consumption.

**Depends on:** K-2 (political entities and demographics define where cultures exist).
**Blocks:** L-2 (settlement stocking uses cultural data), N-1 (LLM narration names things using cultural data).

---

### Phase L — Content Seeding (Setting Generation Layer 6)

---

#### L-1: Dungeon Stocking Pipeline

**Complexity: 3**

Mechanical dungeon generation: layout from gdd-dungeon-layout.md (room placement, corridor routing, door placement on the cell-based grid), faction generation from gdd-dungeon-factions.md (monster distribution, faction territories, patrol routes), trap generation from gdd-trap-generation.md. Produces complete dungeon data files ready for the dungeon exploration loop.

**Depends on:** K-2 (setting data for dungeon placement), D-4 (dungeon grid model).
**Blocks:** L-3 (POI gen counts dungeons toward 45-POI target), M-1 (quest/rumor reads dungeon seeds).

---

#### L-2: Settlement Stocking Pipeline

**Complexity: 3**

Procedural settlement content from gdd-settlement-layout.md: building placement, merchant inventory (filtered by market class), NPC population, henchman availability pool, tavern/inn placement. Produces complete settlement data files for the settlement exploration loop.

**Depends on:** K-2 (demographics, market class), K-3 (cultural data for NPCs), D-5 (settlement grid model).
**Blocks:** L-3 (POI gen counts settlements), M-1 (quest/rumor reads settlement NPC data).

---

#### L-3: POI Generation

**Complexity: 2**

Implements gdd-poi-generation.md. Runs after dungeons and settlements are placed; fills the gap to the 45-POI regional target with lairs, ruins, landmarks, and other points of interest. Each POI gets a mechanical seed (monster type, treasure class, structural type) for later LLM narration.

**Depends on:** L-1 (dungeons counted), L-2 (settlements counted), K-2 (setting terrain for placement).
**Blocks:** M-1 (quest/rumor reads POI data).

---

#### L-4: Encounter Table Construction

**Complexity: 2**

Builds per-hex or per-region encounter tables from the stocked content. Uses HexTerrainData.encounter_table_weights() (already implemented) combined with monster data from the stocked dungeons, lairs, and POIs. Output: encounter tables consumable by the session runner's encounter check system.

**Depends on:** L-1, L-2, L-3 (all content sources for encounter populations).
**Blocks:** E-2's encounter check system (already wired to terrain weights, now gets populated tables).

---

#### L-5: Weather System

**Complexity: 2**

Implements gdd-weather-generation.md. Depends on calendar-seasons (B-3) for season lookup and setting gen (K-1) for Köppen climate codes per hex. Generates daily weather (temperature, precipitation, wind, visibility) that feeds into travel speed modifiers and exploration conditions. The CalendarSeasons static functions and Timekeeping.season_changed signal are already built.

**Depends on:** B-3 (calendar-seasons), K-1 (climate codes).
**Blocks:** E-1 (travel speed weather modifier — can be wired retroactively).

---

### Phase M — Information & Discovery Layer

---

#### M-1: Quest and Rumor System

**Complexity: 3**

Implements gdd-quest-rumor-system.md. Reads dungeon seeds, lair data, POI rumor seeds, and settlement NPC profiles to generate mechanical quest/rumor entries. Feeds notice boards, NPC dialogue, carousing hijink results, quest journal UI. Depends on reputation (G-1) for NPC attitude checks during rumor sharing.

**Depends on:** L-1, L-2, L-3 (content sources), G-1 (reputation for NPC attitudes).
**Blocks:** N-1 (LLM narration writes quest text and rumor phrasing).

---

#### M-2: Region Zoom-In Pipeline

**Complexity: 3**

Generates 6-mile hex detail from 24-mile campaign hexes. A separate pipeline that refines existing broad-stroke data into playable local regions on demand. Triggers when the party enters a 24-mile hex that hasn't been detailed yet.

**Depends on:** K-2 (24-mile campaign map exists), L-1 through L-4 (content seeding pipelines to run at 6-mile scale).
**Blocks:** None strictly (enhancement to existing exploration).

---

### Phase N — LLM Narrative Synthesis (Setting Generation Layer 7)

---

#### N-1: Per-Entity LLM Narration Pass

**Complexity: 3**

Batch LLM pass over all generated mechanical content: POI names/descriptions, NPC names/appearances/dialogue hooks, dungeon room descriptions, settlement building descriptions, quest text, rumor phrasing. Uses context assembly (J-4) with entity-specific context. Runs during setting generation (not at play-time).

**Depends on:** J-4 (context assembly), K-3 (cultural data for naming), L-1 through M-1 (all mechanical content to narrate).
**Blocks:** N-2 (cached narration builds on generated descriptions).

---

#### N-2: Tier 1 Cached LLM Narration

**Complexity: 2**

Pre-generated narration for common events, cached to avoid repeated LLM calls. Generated at setting-creation time or on first encounter. Stored in DB or JSON alongside the mechanical data. Falls back to Tier 0 templates if generation fails.

**Depends on:** N-1 (narration pass produces the cache), J-3 (template fallback).
**Blocks:** N-3 (live narration extends cached narration).

---

#### N-3: Tier 2 Live LLM NPC Interaction

**Complexity: 3**

Real-time LLM-driven NPC dialogue during play. Context assembly includes NPC personality (gdd-npc-personality.md), relationship history, current situation, cultural context. The LLM generates in-character dialogue constrained by the NPC's mechanical state (attitude, knowledge, goals). Must handle latency gracefully (streaming response display, fallback to cached lines).

**Depends on:** N-2 (cached narration as fallback), J-4 (context assembly), G-1 (reputation/attitude).
**Blocks:** None strictly (enhancement layer).

---

#### N-4: Campaign Memory / Narrative Continuity

**Complexity: 3**

Persistent narrative state that the LLM can reference across sessions: notable events, NPC relationships, player decisions, world changes. A structured summary that fits within token budgets and gives the LLM enough context to maintain narrative coherence over long campaigns. Pruning strategy for old/irrelevant memories.

**Depends on:** J-4 (context assembly consumes memories), N-3 (live interaction produces memories).
**Blocks:** None strictly (enhancement layer).

---

### Phase O — Advanced Mechanical Systems

Items in this phase are largely independent of each other and can be built in any order once Phases K–N are stable.

---

#### O-1: Procedural Battle Map Generation

**Complexity: 3**

Implements gdd-combat-map-generation.md. Generates tactical combat maps from terrain context: wilderness battle maps (500′×500′, 100×100 cells, ephemeral unless lair encounter) and dungeon combat maps (use existing room geometry). Terrain features, elevation, cover. Wilderness battle maps are ephemeral unless the encounter is a lair encounter, in which case the map persists.

**Depends on:** F-1 (combat system), D-4 (dungeon grid), K-1 (terrain data).

---

#### O-2: Boss Encounter Tactical AI

**Complexity: 4**

Intelligent monster behavior for significant encounters. Uses gdd_combat_behavior_tags.md for behavior classification. Must handle: spellcasting monsters (spell selection, target priority), retreat triggers, minion coordination, environmental interaction. This is the hardest AI problem in the project.

**Depends on:** F-1 (combat system), O-1 (battle maps for tactical positioning).

---

#### O-3: Batch Pre-Generation (Tier 1.5)

**Complexity: 2**

Background generation of content ahead of player exploration. When the player is in session, pre-generate adjacent hexes, upcoming dungeon levels, NPC dialogue caches. Runs on a background thread or during loading screens. Essentially a scheduling wrapper around existing generation pipelines.

**Depends on:** K-2, L-1 through L-4 (generation pipelines to schedule).

---

#### O-4: NPC Domain Simulation

**Complexity: 3**

Simulated domain turns for NPC-controlled domains. NPC rulers make decisions (expand, build, recruit, wage war) based on personality and strategic situation. The player's domain interacts with NPC domains through trade, diplomacy, and conflict. Uses the domain system (H-1) for resolution.

**Depends on:** H-1 (domain system), G-1 (reputation), K-2 (political entities).

---

#### O-5: Homebrew Content System

**Complexity: 3**

Custom class construction wizard (using ACKS Player's Companion class building rules from pc_classes_*.xml), monster builder, spell research UI. Lets the player create custom content that integrates with the existing registries (ClassRegistry, PowerRegistry, SpellRegistry).

**Depends on:** C-1 (class system), C-2 (spell system), all registries.

---

#### O-6: Language System

**Complexity: 1**

Character language list, language requirements for reading/writing (INT-based literacy rules from ACKS), language barriers in NPC interaction. Data model is simple; the interaction with NPC dialogue (N-3) is the only non-trivial part.

**Depends on:** C-1 (CharacterData language field already exists), N-3 (NPC dialogue for language barriers).

---

## Summary Table

| Phase | Item | Description | Complexity | Status |
|-------|------|-------------|:----------:|--------|
| A-1 | Scaffold & DB | Shared types, schema, migrations, CampaignRepository | — | ✅ |
| A-2 | Override System | OverrideManager, OverridePanel | — | ✅ |
| B-1 | Dice System | DiceSystem autoload, 3 modes, DicePrompt | — | ✅ |
| B-2 | Roll Log | Session-scoped dice_rolls table | — | ✅ |
| B-3 | Timekeeping | Clock, multi-party, calendar-seasons | — | ✅ |
| C-1 | Character Data Model | 25 classes, powers, generator, equipment catalog | — | ✅ |
| C-2 | Spell Catalog | 231 spells, SpellRegistry, RepertoireEngine | — | ✅ |
| — | Spell Hooks | Modifiers, flags, conditions, damage, effects | — | ✅ |
| D-3 | Hex Map | Rendering, terrain taxonomy, fog of war | — | ✅ |
| — | Proficiency Map | proficiency_system_map.md (667 lines) | — | ✅ |
| — | **Test Debt** | **Run all 22 suites in Godot, fix failures** | **1** | **⚠** |
| **C-2b** | **Proficiency Registry** | **Catalog JSON + ProficiencyRegistry class** | **2** | **⏳** |
| C-3 | Character Creation UI | 9-step flow + equipment shop | 3 | ☐ |
| C-4 | Three-Tier Persistence | Tiered storage (full/named/transient), promotion engine | 3 | ☐ |
| C-5 | XP / Level-Up / Aging | XP awards, level-up engine, aging tables | 3 | ☐ |
| D-1 | Asset Registry | Semantic IDs, placeholder generator | 2 | ☐ |
| D-2 | Navigation Stack | Scene transitions, push/pop state machine | 3 | ☐ |
| D-4 | Dungeon Grid | Cell-based walls, room detection, fog | 3 | ☐ |
| D-5 | Settlement Map | Single-district urban grid | 2 | ☐ |
| E-1 | Party Management | Formation, travel speed, splitting | 2 | ☐ |
| E-2 | Session Runner | Core game loop state machine | 4 | ☐ |
| F-1 | Combat Loop | Full ACKS combat sequence | 4 | ☐ |
| G-1 | Reputation System | Per-faction/settlement scoped reputation | 2 | ☐ |
| G-2 | Henchman Lifecycle | Search → hire → adventure → depart | 3 | ☐ |
| H-1 | Domain Layer | Domain model, monthly resolution, strongholds | 4 | ☐ |
| I-1 | Integration Test | Hand-authored test campaign | 3 | ☐ |
| J-1 | LLM Service | Provider abstraction (cloud/local/mock) | 3 | ☐ |
| J-2 | LLM Setup Wizard | Settings UI for provider configuration | 2 | ☐ |
| J-3 | Tier 0 Templates | Pre-written narration templates | 1 | ☐ |
| J-4 | Context Assembly | Prompt building, token budget, logging | 3 | ☐ |
| J-5 | Free-Form Input | Player text → action vocabulary → execution | 3 | ☐ |
| K-1 | Terrain System | Procedural terrain generation | 2 | ☐ |
| K-2 | Setting Gen L1–5 | Geography, demographics, politics, culture | 4 | ☐ |
| K-3 | Culture/Religion Gen | 1:1 culture-religion seeding | 3 | ☐ |
| L-1 | Dungeon Stocking | Layout, factions, traps | 3 | ☐ |
| L-2 | Settlement Stocking | Buildings, merchants, NPCs | 3 | ☐ |
| L-3 | POI Generation | Fill to 45-POI target | 2 | ☐ |
| L-4 | Encounter Tables | Per-hex encounter table construction | 2 | ☐ |
| L-5 | Weather System | Daily weather from climate + season | 2 | ☐ |
| M-1 | Quest/Rumor System | Mechanical quest and rumor generation | 3 | ☐ |
| M-2 | Region Zoom-In | 24-mile → 6-mile detail | 3 | ☐ |
| N-1 | Entity Narration | Batch LLM pass over generated content | 3 | ☐ |
| N-2 | Cached Narration | Pre-generated common event narration | 2 | ☐ |
| N-3 | Live NPC Interaction | Real-time LLM dialogue | 3 | ☐ |
| N-4 | Campaign Memory | Persistent narrative state | 3 | ☐ |
| O-1 | Battle Map Gen | Procedural tactical maps | 3 | ☐ |
| O-2 | Boss Tactical AI | Intelligent monster combat behavior | 4 | ☐ |
| O-3 | Batch Pre-Gen | Background content generation | 2 | ☐ |
| O-4 | NPC Domain Sim | Simulated NPC domain turns | 3 | ☐ |
| O-5 | Homebrew System | Class/monster/spell builder | 3 | ☐ |
| O-6 | Language System | Language list, literacy, barriers | 1 | ☐ |

**Complexity distribution:** 3× complexity 1, 14× complexity 2, 21× complexity 3, 7× complexity 4.
