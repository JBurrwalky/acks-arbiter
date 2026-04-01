# ACKS Arbiter — Master Implementation Roadmap

## Context

The project has a strong foundation after ~14 build sessions: 7 autoloads, 16 shared types, complete character creation (25 classes, 231 spells, 176 equipment items, 106 proficiencies), hex map rendering, dice/timekeeping/calendar/override systems, and 300+ tests across 28 suites. However, **zero gameplay exists** — there is no session runner, no combat, no monsters, no encounters, no treasure, and no exploration loops. The design brief defines two phases: Phase 1 (playable game loop with hand-authored content, zero LLM, zero procgen) and Phase 2 (procedural generation + LLM narration). This roadmap covers Phase 1 in detail and orders Phase 2 at a high level.

The critical path to a playable game is:
**Monster Data → Combat Engine → Encounter System → Session Runner → Exploration Loops → UI → Polish**

### Key Reference: UI/UX Design GDD
`generation/gdd-ui-ux-design.md` defines the complete UI specification:
- **Layout pattern:** Left ~70% map viewport, Right ~30% vertical panel (narrative + actions + text input), bottom status bar
- **Screen IDs:** S-01 through S-05 (shell), G-01 through G-10 (game), O-01 through O-08 (overlays)
- **Visual style:** Dark fantasy vellum, quill-and-ink, medieval manuscript metaphor
- **Combat (G-05):** Full isometric grid specified, but Phase 1 uses hybrid abstract+range bands instead
- **Dungeon (G-03):** Full isometric grid specified, but Phase 1 uses text-based rooms instead
- **Key interaction patterns:** Wilderness click-to-move with route preview, dungeon simultaneous declaration, combat sequential turns with spell declaration phase, day declaration with 8-slot budget

### All GDDs now present (18 files in generation/)
No missing GDDs. `gdd-name-generation.md` and `gdd-settlement-stocking.md` were added during this planning session.

---

## PRE-MILESTONE: Fix Existing Character Creation Issues

Two issues in the current character creation flow must be resolved before proceeding. These are small, self-contained fixes that unblock the rest of the roadmap.

### Fix A — Language Grants During Character Creation [Sonnet, Size S-M]
**Problem:** The character creation wizard has no language assignment step. ACKS grants characters: (a) their alignment language, (b) Common, (c) bonus languages from INT modifier, (d) racial languages (e.g., Elvish, Dwarvish, Gnomish). Languages are best modeled as grants of the existing Language proficiency with specific specialization (e.g., `language_common`, `language_elvish`).
**Approach:**
- Add language data to class JSONs where needed (racial languages for demihuman classes)
- During character creation (between proficiency selection and spell selection, or integrated into proficiency step), auto-grant: Common + alignment language + racial language(s). Then let player pick INT-bonus bonus languages from the Language proficiency's specialization list.
- **Phase 1 workaround for setting-generated languages:** Use a hardcoded "common languages" list (Common, Elvish, Dwarvish, Gnomish, Goblin, Orcish, Draconic, etc.) instead of setting-generated language registries. The SpecializationRegistry already has `language` with 21 entries — use those. If a character's background culture language doesn't exist in the registry, skip gracefully rather than error.
- Store languages as proficiency entries with specialization (consistent with proficiency system) AND populate `CharacterData.languages` JSON field for display.
- Update `character_sheet_panel.gd` to display languages in the finalized sheet.
**Files:** `character_creation_screen.gd` (add language grants to finalization), `character_generator.gd` (add language assignment), `character_sheet_panel.gd` (display languages), potentially a new `language_selection_panel.gd` if INT bonus languages need a picker.

### Fix B — Created Characters Not Visible in Override Panel [Sonnet, Size S]
**Problem:** Characters created via the UI are persisted to the database (`CampaignRepository.create_character()` is called in `_finalize_character()`), but they are never added to the party. The Override panel's Characters tab calls `CampaignRepository.list_party_characters(GameState.party_id)`, which queries the `party_members` junction table — and the character creation flow never calls `CampaignRepository.add_party_member()`.
**Fix:** In `character_creation_screen.gd._finalize_character()`, after persisting the character, call `CampaignRepository.add_party_member(GameState.party_id, character.id)`. This makes the character appear in the Override panel and any future party roster UI.
**Files:** `scenes/ui/character_creation/character_creation_screen.gd` (add `add_party_member` call after `create_character`)

---

## MILESTONE 0: Foundation Gaps (Pre-combat prerequisites)

### 0.1 — Monster Data Schema Design [Opus, Size M]
- **Build:** Design JSON schema for `data/monsters/monster_catalog.json`
- **Read first:** `le_monster_characteristics_stats.xml`, `acore_combat_and_wounds.xml` (attack throw tables by HD), 2+ monster catalog XMLs for source data shape
- **Schema must serve:** combat (attack throws, damage, saves, morale, special abilities), encounters (number appearing, treasure type, XP), future systems (lair data, wilderness frequency, tags for combat AI)
- **Key fields:** monster_key, name, alignment, movement (array of modes), armor_class, hit_dice (parsed: {count, sides, modifier, special_ability_stars}), attacks (array), save_as, morale, treasure_type, xp, number_appearing (dungeon/wilderness variants), percent_in_lair, special_abilities (structured), size_category, intelligence
- **Depends on:** Nothing
- **Produces:** Canonical schema consumed by MonsterRegistry, EncounterGenerator, TreasureGenerator, CombatManager

### 0.2 — Monster Data Extraction (~50-80 core monsters) [Sonnet, Size L]
- **Build:** `data/monsters/monster_catalog.json` — extract from 8 `acore_monster_catalog_*.xml` files
- **Priority monsters:** Skeleton, zombie, goblin, orc, kobold, gnoll, bugbear, ogre, troll, giant (hill), wolf, dire wolf, bear, giant spider, giant rat, bandit/brigand, berserker, bat (giant), centipede (giant), snake (pit viper), lizardman, ghoul, wight, wraith, gargoyle, harpy, minotaur, owlbear, basilisk, medusa, manticore, griffon, dragon (1-2 types), gelatinous cube, carrion crawler, rust monster, stirge, and enough others to populate encounter tables for all terrain types
- **Depends on:** 0.1
- **Produces:** JSON data file with 50-80 entries

### 0.3 — MonsterRegistry [Sonnet, Size S]
- **Build:** `engine/subsystems/monsters/monster_registry.gd` (class MonsterRegistry, RefCounted)
- **Pattern:** Identical to ClassRegistry — loads JSON, provides lookup
- **API:** `get_monster(key)`, `has_monster(key)`, `get_all_keys()`, `get_monsters_by_type(type)`, `get_attack_throw_for_hd(hd_value)`, `get_xp_value(key)`
- **Tests:** `tests/test_monster_registry.gd`
- **Depends on:** 0.2
- **Produces:** Monster lookup consumed by CombatManager, EncounterGenerator, TreasureGenerator

### 0.4 — Level-Up / Advancement Engine [Sonnet, Size M]
- **Build:** `engine/subsystems/characters/advancement_engine.gd` (class AdvancementEngine, RefCounted)
- **Implements:** XP threshold check, HP roll (new HD or flat bonus after max HD), attack/save table updates from class progression, proficiency slot grants, spell slot updates, title change
- **Uses:** ClassRegistry, CharacterData, DiceSystem, ProficiencyRegistry, SpellRegistry
- **Tests:** `tests/test_advancement_engine.gd`
- **Depends on:** Nothing new (all dependencies exist)
- **Produces:** `advance_level(character, class_registry, dice_system) -> Dictionary` of changes; emits `EventBus.character_leveled_up`

**Milestone 0 done when:** MonsterRegistry loads 50+ monsters with tests passing. AdvancementEngine can level up any of 25 classes correctly. All 28 prior test suites still pass.

---

## MILESTONE 1: Combat Engine Core

### 1.1 — CombatState Data Model [Opus design / Sonnet impl, Size M]
- **Build:** `engine/subsystems/combat/combat_state.gd` (class CombatState, RefCounted)
- **Fields:** encounter_id, round_number, phase (enum: SURPRISE, DECLARATION, INITIATIVE, ACTION, MORALE, CLEANUP), combatants (Dict of id -> CombatantEntry), initiative_order, is_surprise_round, active_combatant_index
- **CombatantEntry:** entity_id, entity_type ("pc"|"henchman"|"npc"|"monster"), side, group_id (monster initiative grouping), initiative_roll, hp_current, hp_max, status ("active"|"retreating"|"fled"|"unconscious"|"dead"), declared_action, attacks_remaining (cleave), movement_remaining, **position: Vector2i** (grid x,y — always tracked even in Phase 1 abstract mode), **range_band: enum (MELEE, CLOSE, FAR)** — derived from position data, used by Phase 1 UI; Phase 2 isometric renderer reads positions directly
- **Factory:** `from_encounter(encounter_data, party_characters, monster_registry) -> CombatState`
- **Depends on:** CharacterData, EncounterData, MonsterRegistry (0.3)
- **Produces:** State container consumed by all combat subsystems

### 1.2 — Initiative Resolver [Sonnet, Size S]
- **Build:** `engine/subsystems/combat/initiative_resolver.gd`
- **Rules:** Each PC rolls 1d6 + DEX mod individually; each monster group rolls 1d6 shared. Higher first; ties simultaneous.
- **Depends on:** CombatState (1.1), DiceSystem, CharacterData
- **Tests:** `tests/test_initiative_resolver.gd`

### 1.3 — Attack Resolution Engine [Sonnet, Size M-L]
- **Build:** `engine/subsystems/combat/attack_resolver.gd`
- **Implements:** d20 attack throw (attacker's attack_throw + target_AC >= roll), STR/DEX modifiers, magic bonuses, situational modifiers (-4 invisible, +2 prone, +4 held, +2 charge, range penalties), natural 1/20, damage roll with modifiers, charge double damage
- **Depends on:** CombatState, CharacterData (effective getters), InventoryItem (weapons), MonsterRegistry, DiceSystem, ModifierStack
- **Tests:** `tests/test_attack_resolver.gd`
- **Produces:** `resolve_attack(attacker, defender, weapon, modifiers) -> AttackResult`

### 1.4 — Cleave Handler [Sonnet, Size S]
- **Build:** Integrated into attack flow or separate `engine/subsystems/combat/cleave_handler.gd`
- **Rules:** Fighter: HD cleaves, Cleric/Thief: HD/2, Mage: 0. Missile limits by weapon type. Target must be within 5ft of downed enemy.
- **Depends on:** AttackResolver (1.3), CombatState, ClassRegistry (combat_progression)
- **Tests:** included in attack resolver tests

### 1.5 — Morale Resolver [Sonnet, Size S]
- **Build:** `engine/subsystems/combat/morale_resolver.gd`
- **Rules:** 2d6 + morale rating. Triggers: first death, 50% casualties, solo monster at 50% HP. Results: retreat/fighting withdrawal/fight on/advance.
- **Depends on:** CombatState, MonsterRegistry, DiceSystem
- **Tests:** `tests/test_morale_resolver.gd`

### 1.6 — Saving Throw Resolver [Sonnet, Size S]
- **Build:** `engine/subsystems/combat/saving_throw_resolver.gd`
- **Implements:** d20 >= target. Characters use CharacterData.get_effective_save(). Monsters save by HD or class/level equivalent. Modifier stacking from spells/proficiencies/items.
- **Depends on:** CharacterData, MonsterRegistry, DiceSystem
- **Tests:** `tests/test_saving_throw_resolver.gd`

### 1.7 — Mortal Wounds & Tampering [Opus interpretation / Sonnet impl, Size M]
- **Build:** `engine/subsystems/combat/mortal_wounds_resolver.gd`
- **Rules:** d20+d6 table from `ax_mortal_wounds_and_tampering.xml`. Modifiers: CON, HD, HP deficit, healing magic, healing proficiency, treatment timing. Permanent wound sub-tables by damage type.
- **Depends on:** CharacterData, DiceSystem, Timekeeping, ConditionCatalog
- **Tests:** `tests/test_mortal_wounds.gd`

### ~~1.8 — Special Maneuvers~~ *DEFERRED TO PHASE 2*
- All 8 special maneuvers (disarm, force back, knock down, overrun, sunder, wrestle, incapacitate, brawl) deferred. Phase 1 has attack/cleave/morale/mortal wounds only.

### 1.8 — Combat Manager (Round Orchestrator) [Opus design / Sonnet impl, Size XL]
- **Build:** `engine/subsystems/combat/combat_manager.gd` (class CombatManager, extends Node)
- **Implements:** Full round sequence: declaration → initiative → action resolution (iterate order, resolve attacks/spells/movement/maneuvers) → morale check → cleanup (remove dead, check victory). Manages cleave chaining, spell interruption, concentration breaking.
- **Depends on:** All of 1.1-1.7, DiceSystem, Timekeeping, EventBus (combat_started, round_resolved, combatant_downed, combat_ended)
- **Tests:** `tests/test_combat_manager.gd` — integration tests with overridden dice
- **Produces:** `start_combat()`, `declare_action()`, `resolve_round()`, `end_combat()`

**Milestone 1 done when:** A scripted combat test runs to completion: 4 PCs vs 6 goblins, with initiative, attacks, damage, cleave, morale, and mortal wounds all resolving correctly via overridden dice.

---

## MILESTONE 2: Encounter & Reaction System

### 2.1 — Reaction / Social Resolver [Opus rules / Sonnet impl, Size M]
- **Build:** `engine/subsystems/social/reaction_resolver.gd`
- **Rules from:** `ax_reactions_and_influencing.xml` — 2d6 + CHA mod → attitude, three tones (diplomatic/intimidating/seductive), attempt escalation
- **Depends on:** DiceSystem, CharacterData
- **Tests:** `tests/test_reaction_resolver.gd`

### 2.2 — Hand-Authored Encounter Tables [Sonnet, Size S]
- **Build:** `data/encounters/encounter_tables.json` — weighted tables per terrain type (clear, woods, jungle, swamp, desert, mountains, ocean, city, inhabited), ~8-12 monster entries each, drawn from the 50-80 monsters in catalog
- **Depends on:** Monster catalog (0.2), HexTerrainData encounter weight categories

### 2.3 — Encounter Generator [Sonnet, Size M]
- **Build:** `engine/subsystems/encounters/encounter_generator.gd`
- **Implements:** Terrain-based monster selection from weighted tables, number appearing roll, reaction roll, surprise check (1d6, surprised on 1-2), encounter distance by terrain
- **Depends on:** MonsterRegistry, HexTerrainData, DiceSystem, ReactionResolver (2.1), encounter tables (2.2)
- **Tests:** `tests/test_encounter_generator.gd`
- **Produces:** `generate_encounter(terrain, territory, dice) -> EncounterData`

### 2.4 — Evasion & Pursuit [Sonnet, Size S]
- **Build:** Extend EncounterGenerator with evasion rules (movement rate comparison, terrain modifiers)
- **Depends on:** EncounterGenerator (2.3), party movement rate
- **Tests:** included in encounter generator tests

**Milestone 2 done when:** Encounters generate from terrain data with correct reaction rolls and surprise. Reaction system handles all three tones with attitude transitions.

---

## MILESTONE 3: Session Runner & Wilderness Loop

### 3.1 — Action Vocabulary Registry [Sonnet, Size S]
- **Build:** `engine/subsystems/session/action_vocabulary.gd`
- **Phase 1 actions:** move_to_hex, camp, explore_hex, search_area, enter_settlement, enter_dungeon, attack_melee, attack_missile, cast_spell, use_item, flee, negotiate, rest, force_march, forage
- **Depends on:** ActionPayload (existing)

### 3.2 — Session Runner Core [Opus design / Sonnet impl, Size XL]
- **Build:** `engine/subsystems/session/session_runner.gd` (extends Node, child of Main scene)
- **Implements:** Present state → receive input → validate action → resolve → present new state. Manages GameState transitions. Delegates to context handlers (WildernessHandler, DungeonHandler, CombatHandler, CampHandler). Owns transition triggers.
- **Depends on:** GameState, EventBus, CampaignRepository, Timekeeping, CombatManager (1.9), EncounterGenerator (2.3), ActionVocabulary (3.1)
- **Tests:** `tests/test_session_runner.gd`

### 3.3 — Wilderness Exploration Handler [Sonnet, Size M-L]
- **Build:** `engine/subsystems/session/wilderness_handler.gd`
- **Implements:** Daily travel (movement cost by terrain, base 24 mi/day modified by encumbrance/terrain), encounter check per hex (1-in-6 wilderness, 1-in-10 civilized, 1-in-3 borderlands), getting-lost check, foraging (1-in-6 per day, terrain-modified), supply consumption, forced march
- **Depends on:** HexMapController, HexTerrainData, Timekeeping, EncounterGenerator, DiceSystem
- **Tests:** `tests/test_wilderness_handler.gd`

### 3.4 — Camp / Rest Handler [Sonnet, Size M]
- **Build:** `engine/subsystems/session/camp_handler.gd`
- **Implements:** Watch scheduling (3 watches/night), rest HP recovery (1d3/day), encounter checks per watch, spell memorization
- **Depends on:** Timekeeping, EncounterGenerator, DiceSystem, CharacterData
- **Tests:** `tests/test_camp_handler.gd`

### 3.5 — Tier 0 Template Narrator [Sonnet, Size M]
- **Build:** `engine/subsystems/narration/template_narrator.gd`
- **Implements:** Token-substituted templates for all Phase 1 events: movement, combat, encounters, camp, rest, treasure, level-up. Templates in `data/narration/templates.json`.
- **Depends on:** All event types from EventBus
- **Tests:** `tests/test_template_narrator.gd`

### 3.6 — Hand-Authored Test Campaign [Sonnet, Size M]
- **Build:** `data/test_campaign/` — expanded hex map (~60 hexes, all terrain types, 2-3 settlements, 1-2 dungeon entrances), pre-built party of 4 PCs, scripted encounters, simple 3-room dungeon
- **Depends on:** Monster catalog, EncounterData, hex map format, dungeon data model

**Milestone 3 done when:** Player can load test campaign, move party across hexes with correct movement costs, trigger encounter checks, resolve encounters through combat or reaction, camp/rest, and see template narration. Complete wilderness loop with zero LLM.

---

## MILESTONE 4: Dungeon Exploration Loop

### 4.1 — Dungeon Data Model [Opus design / Sonnet impl, Size M]
- **Build:** `engine/shared_types/dungeon_data.gd` (class DungeonData, RefCounted)
- **Fields:** rooms (id, position, exits, contents, is_explored), corridors, doors (state, type), traps, light state
- **Depends on:** EncounterData, InventoryItem
- **DB persistence:** from_dict()/to_dict() for save/load

### 4.2 — Dungeon Exploration Handler [Sonnet, Size L]
- **Build:** `engine/subsystems/session/dungeon_handler.gd`
- **Implements:** 10-min turns, wandering monsters (1-in-6 per 2 turns), light sources (torch=6 turns, lantern=24 turns/flask), search (10x10, 1 turn), listen (1 round, 18+ throw), open stuck door (STR 18+), trap detection (18+ on d20, dwarves 14+), 5-turn active/1-turn rest cycle
- **Depends on:** DungeonData, Timekeeping, EncounterGenerator, DiceSystem, CombatManager
- **Tests:** `tests/test_dungeon_handler.gd`

**Milestone 4 done when:** Party enters test dungeon, explores room-by-room with turn tracking, wandering monsters, light management, and trap detection.

---

## MILESTONE 5: Treasure & XP Flow

### 5.1 — Treasure Type Tables [Sonnet, Size M]
- **Build:** `data/treasure/treasure_types.json` + `engine/subsystems/treasure/treasure_generator.gd`
- **Implements:** Types A-R from `acore_treasure_and_magic_items_rules.xml`: per-column rolls for cp/sp/ep/gp/pp, gems, jewelry. Phase 1: no magic items.
- **Depends on:** MonsterRegistry (treasure_type), DiceSystem, InventoryItem
- **Tests:** `tests/test_treasure_generator.gd`

### 5.2 — Adventure Pool & XP Banking [Sonnet, Size M]
- **Build:** `engine/subsystems/characters/adventure_pool.gd` (class AdventurePool, RefCounted)
- **Implements per GDD §4.8:** Adventure pool accumulates monster XP + treasure GP value during adventuring. XP is NOT distributed after each combat — it banks in the pool. **Settlement banking event** triggers on entering a friendly settlement: total pool divided per ACKS formula (equal shares, henchmen half share, XP adjustment %), pool resets to zero. "Bank later" option available. Split party rules: monster XP goes to first party reaching settlement, treasure XP goes to party carrying the treasure.
- **Also:** Reserve XP tracking per character (frivolous spending → reserve XP bank → transfers to replacement PC on death)
- **Depends on:** MonsterRegistry (XP values), AdvancementEngine (0.4), CharacterData, EventBus (settlement_entered signal)
- **Tests:** `tests/test_adventure_pool.gd`
- **DB:** New `adventure_pool` table or columns on `parties` for pool state persistence

### 5.3 — XP Distribution & Level-Up Trigger [Sonnet, Size S]
- **Build:** Part of AdventurePool — `distribute_pool(party) -> Dictionary` calculates per-character shares, applies XP adjustment %, awards XP, checks level-up thresholds, triggers AdvancementEngine.
- **Depends on:** AdventurePool (5.2), AdvancementEngine (0.4)

**Milestone 5 done when:** Post-combat treasure generates from monster treasure types. Monster XP and treasure GP accumulate in the adventure pool. Entering a settlement triggers banking with correct per-character shares. Characters level up when thresholds are crossed.

---

## MILESTONE 6: Minimal Settlement Interaction (Menus-Only)

Phase 1 needs settlement interaction because: (a) XP banks on settlement entry (GDD §4.8), (b) treasure XP comes from selling loot, (c) equipment resupply between adventures, (d) henchman hiring (future). Phase 1 uses a menus-only settlement — no spatial map, no block graph, no street network. Just market class + service menus. In Phase 2, these menu interfaces get distributed to specific POIs once settlements are fully mapped and stocked per `gdd-settlement-layout.md` and `gdd-settlement-stocking.md`.

### 6.1 — Settlement Data Model [Sonnet, Size S-M]
- **Build:** `engine/shared_types/settlement_data.gd` (class SettlementData, RefCounted)
- **Fields:** settlement_id, name, hex_coord, market_class (I-VI), population, ruler_name, alignment, services_available (array of service type flags), is_hostile. Equipment availability limits derived from market_class per ACKS rules in `acore_equipment.xml`.
- **Phase 1:** Hand-authored settlement entries in the test campaign JSON. No generation.
- **Depends on:** Nothing new
- **Produces:** Data model consumed by commerce system and settlement screen
- **DB:** Add to hex_cells or new settlements table (migration 010)

### 6.2 — Commerce Engine (Buy/Sell/Commission) [Sonnet, Size M]
- **Build:** `engine/subsystems/commerce/commerce_engine.gd` (class CommerceEngine, RefCounted)
- **Implements:**
  - **Equipment availability** by market class (ACKS price category thresholds: items up to X gp freely available, items up to Y gp limited, items above Z gp must be commissioned)
  - **Buy:** Purchase items from EquipmentCatalog filtered by settlement market class availability. Deduct gold from party inventory.
  - **Sell:** Sell treasure items (gems, jewelry, trade goods, equipment) at market value. Gems/jewelry sell at face value. Equipment sells at 50% (used goods per ACKS). GP value of sold treasure adds to the adventure pool's treasure XP.
  - **Commission:** Order unavailable items for delivery. Completion time per GDD §7.1 (1 day per 5gp value for equipment, etc.)
  - **Monthly stock refresh** (simplified Phase 1: full refresh each month, no per-shop tracking)
- **Depends on:** EquipmentCatalog (existing), SettlementData (6.1), InventoryItem, Timekeeping
- **Tests:** `tests/test_commerce_engine.gd`
- **Produces:** `buy_item(item_key, quantity, settlement) -> bool`, `sell_item(inventory_item, settlement) -> int` (returns GP value), `get_available_items(settlement) -> Array`, `commission_item(item_key, settlement) -> Dictionary`

### 6.3 — Settlement Entry & XP Banking Integration [Sonnet, Size S-M]
- **Build:** Wire settlement entry into SessionRunner and AdventurePool
- **Implements:** When party enters a friendly settlement hex: (a) fire EventBus.settlement_entered, (b) trigger adventure pool XP banking prompt, (c) show settlement services menu. Settlement exit returns to wilderness exploration.
- **Depends on:** AdventurePool (5.2), SessionRunner (3.2), SettlementData (6.1)

### 6.4 — Hireling Availability (Stub for Phase 1) [Sonnet, Size S]
- **Build:** Basic hireling/mercenary availability lookup by market class. Phase 1: display available hirelings from `provisions_services.json` wage tables filtered by market class. No hiring flow yet (henchman lifecycle is Phase 2). Just "these hirelings are available at these wages."
- **Depends on:** SettlementData (6.1), provisions_services.json data

**Milestone 6 done when:** Party can enter a settlement, see available services menu, buy/sell equipment and treasure, bank XP from the adventure pool, and commission items. Selling gems/jewelry adds to treasure XP correctly. Market class correctly limits what's available.

---

## MILESTONE 7: Gameplay UI (per gdd-ui-ux-design.md)

All screens follow the GDD's 70/30 layout pattern: left viewport + right narrative/action panel + bottom status bar. Dark fantasy vellum visual style. **Note:** Milestone numbers 7-9 shift from the original 6-8.

### 7.1 — Shell Screens: Main Menu (S-01), Campaign List (S-02), Campaign Creation (S-03) [Sonnet, Size M]
- **Build:** `scenes/ui/shell/main_menu.gd`, `campaign_list.gd`, `campaign_creation.gd` + `.tscn` files
- **Implements:** Main menu (New/Continue/Load/Settings/Quit), campaign list with party summaries, campaign creation wizard (Phase 1: skip setting generation steps, go straight to character creation). Note: S-04 (Character Creation) already exists.
- **Depends on:** CampaignRepository, existing character creation screen

### 7.2 — Session Status Bar (cross-screen, §4.13) [Sonnet, Size S-M]
- **Build:** `scenes/ui/components/session_status_bar.gd` + `.tscn`
- **Implements:** Party indicator, location, time/date, day budget (8-slot), adventure pool, party member chips (portrait + HP bar + conditions), movement mode, light source (dungeon only). Fixed bottom bar shared by all G-screens.
- **Depends on:** GameState, Timekeeping, CharacterData

### 7.3 — Wilderness Exploration Screen (G-01) [Sonnet, Size M-L]
- **Build:** `scenes/ui/exploration/wilderness_screen.gd` + `.tscn`
- **Implements:** Left 70%: hex map viewport with click-to-move (legal targets highlighted by remaining movement, route preview, confirm button). Right 30%: narrative panel (top), action buttons (Move/Camp/Forage/Search/Rest/Scout/Enter Settlement/Enter Dungeon), text input (bottom). Collapsible roll log from left edge.
- **Depends on:** SessionRunner, WildernessHandler, hex map renderer, TemplateNarrator, session status bar

### 7.4 — Combat Screen (G-05, Phase 1 Hybrid) [Sonnet, Size M-L]
- **Build:** `scenes/ui/combat/combat_screen.gd` + `.tscn`
- **Phase 1 hybrid:** Instead of full isometric grid, uses abstract list with **range bands** (melee/close/far). Right panel: initiative order list, active combatant stats, action buttons (Attack Melee/Ranged, Cast Spell, Use Item, Fighting Withdrawal, Full Retreat, Other), combat log. Spell declaration phase prompt at round start per §3.7. Range band display shows who's at what range from whom.
- **Full isometric grid (G-05 as designed in GDD) deferred to Phase 2.**
- **Depends on:** CombatManager, CombatState, TemplateNarrator

### 7.5 — Encounter Screen (G-04) [Sonnet, Size M]
- **Build:** `scenes/ui/encounter/encounter_screen.gd` + `.tscn`
- **Implements:** Three branches per §3.5: Branch A (hostile → auto-transition to combat), Branch B (uncertain → narrative + text input + fallback buttons: Attack/Flee/Parley/Intimidate/Offer Gold), Branch C (friendly → brief narration + continue).
- **Depends on:** EncounterGenerator, ReactionResolver, CombatManager, TemplateNarrator

### 7.6 — Dungeon Screen (G-03, Phase 1 Text-Based) [Sonnet, Size M]
- **Build:** `scenes/ui/dungeon/dungeon_screen.gd` + `.tscn`
- **Phase 1:** Text-based room descriptions, exit list, party member positions as text, light/turn indicators. Right panel: action buttons (Move/Search/Listen/Check Traps/Open Door/Spike Door/Use Item/Rest/End Turn). Simultaneous declaration → "End Turn" execution per §3.3.
- **Full isometric renderer (G-03 as designed in GDD) deferred to Phase 2.**
- **Depends on:** DungeonHandler, DungeonData, TemplateNarrator

### 7.7 — Camp/Rest Screen (G-06) [Sonnet, Size S-M]
- **Build:** `scenes/ui/camp/camp_screen.gd` + `.tscn`
- **Implements:** Watch assignment (drag character chips into watch slots per §3.8), per-watch resolution with narrative, rest results summary (HP/spells recovered, supplies consumed, time advanced).
- **Depends on:** CampHandler, TemplateNarrator

### 7.8 — Settlement Screen (G-02, Phase 1 Menus-Only) [Sonnet, Size M]
- **Build:** `scenes/ui/settlement/settlement_screen.gd` + `.tscn`
- **Phase 1:** No city map — pure menu interface. Header shows settlement name, market class, population. Service tabs: **Buy Equipment** (EquipmentCatalog filtered by market class availability), **Sell Treasure** (list party inventory, sell at market/50% value, GP added to adventure pool treasure total), **Commission Items** (order unavailable items with delivery time), **Services** (lodging, stabling from provisions_services.json), **Hirelings** (view available, no hire flow yet). **Bank XP** button triggers adventure pool distribution. **Leave Settlement** returns to wilderness.
- **Phase 2 upgrade path:** These menu interfaces become individual POI interactions once settlements have spatial maps. Buy → specific shop POIs. Sell → specific merchant POIs. Services → specific inns/stables. The underlying CommerceEngine API stays the same.
- **Depends on:** CommerceEngine (6.2), AdventurePool (5.2), SettlementData (6.1), EquipmentCatalog, TemplateNarrator

### 7.9 — Pause Menu (O-01) + Settings (S-05) [Sonnet, Size S-M]
- **Build:** `scenes/ui/shell/pause_menu.gd`, update existing settings
- **Implements:** Escape overlay (Resume/Save/Load/Settings/Main Menu), settings screen with display/dice mode/roll transparency/map overlays/LLM provider sections. Phase 1: LLM provider = Offline only.

**Milestone 7 done when:** Full navigation flow works: Main Menu → Campaign Creation → Character Creation → Wilderness Exploration → Encounter → Combat → Settlement (buy/sell/bank XP) → Camp → back to Exploration. All screens use the 70/30 layout with status bar. Vellum scroll transitions between map levels.

---

## MILESTONE 8: Spell Resolution & Effect Wiring

### 8.1 — ActiveEffectTracker ↔ Timekeeping Connection [Sonnet, Size S]
- **Build:** Wire existing systems — connect Timekeeping signals to ActiveEffectTracker tick methods
- **Depends on:** Both systems exist; just needs connection + integration tests

### 8.2 — Priority Spell Effect Population [Sonnet, Size M]
- **Build:** Expand `spell_effects.json` from 13 → ~40-50 entries covering all L1-3 combat/exploration spells
- **Priority:** Cure Light Wounds, Hold Person, Sleep, Shield, Magic Missile, Fireball, Lightning Bolt, Web, Invisibility, Light, Detect Magic, Dispel Magic, Charm Person, Protection spells

### 8.3 — Spell Resolution Pipeline [Sonnet impl / Opus edge cases, Size L]
- **Build:** `engine/subsystems/spells/spell_resolver.gd`
- **Implements:** Apply modifiers from SpellEffectRegistry to CharacterData, set flags, apply conditions, saving throws for targets, concentration, dispel checks
- **Depends on:** SpellEffectRegistry, ActiveEffectTracker + 7.1, CharacterData, DiceSystem, SavingThrowResolver (1.6)
- **Tests:** `tests/test_spell_resolver.gd`

**Milestone 8 done when:** L1-3 spells resolve with mechanical effects, durations tick with game time, saving throws work for targets.

---

## MILESTONE 9: Phase 1 Polish & Completion

### 9.1 — Weather System (Simplified) [Opus design / Sonnet impl, Size L]
- **Build:** `engine/subsystems/weather/weather_generator.gd` per `gdd-weather-generation.md`
- **Implements:** Daily weather per hex, 6 channels, mechanical effects on movement/encounters/foraging, dawn/dusk times
- **Depends on:** CalendarSeasons, HexTerrainData, Timekeeping

### 9.2 — Supply & Encumbrance Integration [Sonnet, Size S-M]
- **Build:** Wire EncumbranceCalculator into exploration loop: movement rate adjustment, daily rations/water consumption, mount capacity, forage integration
- **Depends on:** EncumbranceCalculator, WildernessHandler

### 9.3 — Party Management (Split/Merge, Formation) [Sonnet, Size M]
- **Build:** Formation slots (point/front/middle/rear), travel speed = slowest, party split/merge with Timekeeping sync
- **Depends on:** CampaignRepository (party tables), Timekeeping (multi-party clocks)

### 9.4 — Settings Screen & LLM Setup Wizard [Sonnet, Size M]
- **Build:** `scenes/ui/settings/settings_screen.gd`, `llm_setup_wizard.gd`
- **Phase 1:** Only "Offline" mode works. Wizard UI built, cloud/local stubs.

### 9.5 — Level-Up UI [Sonnet, Size M]
- **Build:** `scenes/ui/character_creation/level_up_panel.gd`
- **Implements:** HP roll, proficiency selection (reuse proficiency_selection_panel patterns), spell updates, review changes
- **Depends on:** AdvancementEngine (0.4), ProficiencyRegistry, SpellRegistry

### 9.6 — Map Resume & Known Bug Fixes [Sonnet, Size S]
- **Build:** Fix load_map() fog reset (use DB-persisted fog), wire game_day to Timekeeping in dice_rolls, snapshot restore reloading HexMapController, player_roll() timeout
- **Depends on:** Existing systems

---

## PHASE 1 COMPLETE CRITERIA

The game is playable end-to-end with zero LLM and zero procedural generation:
- Create campaign, create characters, form party
- Explore hand-authored hex map with weather
- Trigger and resolve encounters (combat or social)
- Explore hand-authored dungeon with turn/light tracking
- **Enter settlements: buy/sell equipment, sell treasure, commission items**
- **Bank XP at settlement entry (adventure pool distribution)**
- Earn treasure and XP, level up characters
- Manage supplies, camp/rest
- All narration via Tier 0 templates
- All dice modes (digital/physical/hybrid) work
- Override system works for debugging

---

## PHASE 2 HIGH-LEVEL ORDERING (Post-Phase 1)

1. **NPC Personality System** (GDD exists → feeds henchman lifecycle, LLM context)
2. **Henchman Lifecycle** (needs NPC personality + reaction + char generator)
3. **LLM Provider Implementation** (cloud + local for Tier 1-2 narration)
4. **Setting Generation Pipeline** (8-layer world gen → needs all terrain/weather/encounter infra)
5. **Dungeon Layout Generator** (procedural dungeon maps)
6. **Settlement Layout + Stocking** (Voronoi wards, on-demand stocking)
7. **Domain System** (strongholds, monthly resolution, NPC domain AI — huge, independent track)
8. **Hijinks System** (criminal enterprises, needs settlements)
9. **Mercantile System** (arbitrage, needs market class data)
10. **Magic Research** (spell research, item creation, needs downtime loop)
11. **Monster Catalog Expansion** (L&E monsters, full catalog)
12. **Full Spell Effect Population** (231 spells)
13. **Combat AI / Behavior Tags** (GDD exists)
14. **Battle Map Generation** (procedural combat maps)
15. **Mass Warfare** (DaW rules, abstract resolution for v1)

---

## PARALLEL BUILD TRACKS

| Track A: Combat Critical Path | Track B: Data & Support Systems | Track C: UI |
|---|---|---|
| 0.1-0.3 Monster data/registry | 0.4 Advancement Engine | (blocked until M3+) |
| 1.1-1.8 Combat engine | 2.1 Reaction System | |
| 2.3 Encounter Generator | 2.2 Encounter Tables | |
| 3.2 Session Runner | 3.1 Action Vocabulary | 7.1 Shell Screens |
| 3.3 Wilderness Handler | 3.4 Camp Handler | 7.2 Status Bar |
| 4.2 Dungeon Handler | 3.5 Template Narrator | 7.3-7.9 Game Screens |
| 8.3 Spell Resolution | 5.1-5.3 Treasure & XP | |
| | 6.1-6.4 Settlement/Commerce | |

Track B items can proceed in parallel with Track A once interfaces are defined. Track C should wait until the underlying systems exist to avoid building UI for nonexistent mechanics. Settlement (M6) can be built in parallel with Dungeon (M4) since they share no dependencies.

---

## ESTIMATED SESSION COUNT

| Milestone | Estimated Sessions | Model Mix |
|---|---|---|
| M0: Foundation Gaps | 2-3 | 1 Opus + 1-2 Sonnet |
| M1: Combat Engine | 4-6 | 1 Opus design + 3-5 Sonnet |
| M2: Encounters & Reactions | 2-3 | 1 Opus + 1-2 Sonnet |
| M3: Session Runner & Wilderness | 3-4 | 1 Opus design + 2-3 Sonnet |
| M4: Dungeon Loop | 2-3 | 1 Opus design + 1-2 Sonnet |
| M5: Treasure & XP | 1-2 | Sonnet only |
| M6: Minimal Settlement | 2-3 | Sonnet only |
| M7: Gameplay UI (9 screens) | 5-7 | Sonnet only |
| M8: Spell Resolution | 2-3 | Sonnet mostly |
| M9: Polish | 3-4 | Mixed |
| **Total Phase 1** | **~26-39 sessions** | |

---

## VERIFICATION PLAN

### Per-Milestone Testing
Each milestone has a "done when" criterion above. Additionally:
- **Every new subsystem** gets a dedicated test file with unit tests (dice overrides for deterministic testing)
- **Every milestone boundary** runs the full test suite (`test_runner.tscn`) to catch regressions
- **Milestones 3, 4, 6** include manual playtesting of the game loop

### End-to-End Phase 1 Smoke Test
When all 9 milestones are complete, this scenario must work:
1. Launch game → Main Menu (S-01) → New Campaign
2. Create 4 characters (Fighter, Cleric, Mage, Thief) via existing character creation wizard
3. Enter wilderness exploration (G-01) on the hand-authored test map
4. Move party across hexes — movement costs vary by terrain, time advances
5. Trigger a wilderness encounter — reaction roll determines Branch A/B/C
6. Enter combat (G-05 hybrid) — initiative, attacks, damage, cleave, morale, mortal wounds
7. Win combat → treasure generates from monster treasure type → adventure pool accumulates
8. Camp and rest (G-06) — watch assignment, encounter checks, HP/spell recovery
9. Enter dungeon (G-03 text) — room exploration, turn/light tracking, wandering monsters
10. Dungeon combat → mortal wounds on downed PC
11. Return to wilderness → travel to settlement
12. **Enter settlement (G-02 menus) → sell treasure (gems/jewelry/loot at market value) → treasure GP adds to adventure pool**
13. **Buy replacement equipment from market-class-limited catalog → commission plate armor for delivery**
14. **Bank XP → adventure pool distributes (monster XP + treasure GP) → per-character shares with henchman half-share and XP adjustment**
15. **Level-up triggers if threshold crossed → level-up UI (O-08) → HP roll, proficiency pick, spell slots**
16. Leave settlement → continue adventuring
17. Save game → Load game → resume at correct state
18. All narration via Tier 0 templates throughout
19. Override panel works to modify any game state
20. All three dice modes (digital/physical/hybrid) work

### Key Decisions Made During Planning
- **Combat Phase 1:** Hybrid abstract + range bands (melee/close/far), NOT full isometric grid. CombatState stores x,y positions for Phase 2 readiness.
- **Dungeon Phase 1:** Text-based rooms, NOT graphical renderer.
- **Special maneuvers:** Deferred to Phase 2. Phase 1 has attack/cleave/morale/mortal wounds only.
- **Build order:** Breadth-first (get wilderness + dungeon + combat all working basic, then polish).
- **Monster scope:** ~50 core monsters before combat engine.
- **XP banking:** Full adventure pool with settlement banking per GDD §4.8, NOT immediate distribution.
- **Settlement Phase 1:** Menus-only (no spatial map). Buy/sell/commission + XP banking. Menu interfaces migrate to individual POIs in Phase 2 when settlements get spatial maps per gdd-settlement-layout.md.
- **Treasure XP:** Comes from GP value of treasure sold at settlement, not just found. Gems/jewelry at face value, equipment at 50%.
- **UI layout:** Per gdd-ui-ux-design.md — 70/30 split, vellum aesthetic, screen IDs S-01 through G-10.
- **All GDDs now present:** 18 files in generation/. No missing documents.
- **Languages:** Modeled as Language proficiency with specialization. Auto-grant Common + alignment + racial. INT bonus = player picks from specialization list. Phase 1 uses hardcoded common language list (21 entries already in SpecializationRegistry).
- **Character persistence:** Fix B ensures created characters are added to party via `add_party_member()`, making them visible in Override panel and all party queries.
