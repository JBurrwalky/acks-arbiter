# Rule System Map

Maps game systems to their source files and cross-dependencies.
Read this every session to understand which systems are affected by your current task.

## How to Use

When working on system X:
1. Load the XML files listed under that system
2. Check **Depends on** for upstream systems that may constrain your work
3. Check **Depended on by** for downstream systems you might break
4. Load relevant GDDs if doing generation work

## Companion Documents

- `docs/document_map.md` — inventory of all XML summaries, GDDs, and support docs
- `docs/coding_conventions.md` — implementation patterns for GDScript, SQLite, testing, and cross-subsystem contracts
- `docs/acks_arbiter_build_plan.md` — dependency-ordered build roadmap and current implementation status
- `docs/spell_system_map.md` — spell hook map for any subsystem touched by spell effects
- `docs/proficiency_system_map.md` — proficiency hook map for any subsystem touched by proficiency effects
- `docs/monster_system_map.md` — monster special-ability hook map for any subsystem touched by monster mechanics

---

## Systems

### Character Creation & Classes
- **Rule files:** `acore_basics_and_characters`, `acore_core_classes`, `acore_demihuman_classes`, `acore_campaign_classes`, `pc_classes_1`, `pc_classes_2`, `pc_classes_3`, `pc_classes_4`, `ax_venturer_class`, `ax_non_combatants`
- **GDDs:** `gdd-proficiency-specializations`, `gdd-henchman-class-selection` (0th-level to 1st-level transition)
- **Depends on:** Proficiencies, Equipment (starting gear/wealth)
- **Depended on by:** Combat, Magic, Domain Play, NPC Systems, Campaign Play

### Combat & Conditions
- **Rule files:** `acore_combat_and_wounds`, `ax_conditions_catalog`, `ax_mortal_wounds_and_tampering`
- **GDDs:** `gdd_combat_behavior_tags`
- **Depends on:** Characters (attack throws, saves), Equipment (weapons, armor), Spells (combat spells), Monsters (stat blocks)
- **Depended on by:** All exploration contexts (wilderness, dungeon, urban, sea), Armies & Warfare

### Spells & Magic
- **Rule files:** `acore_spellcaster_rules`, `acore_spell_catalog_a-i_summary`, `acore_spell_catalog_k-w_summary`, `pc_spell_catalog_a-e`, `pc_spell_catalog_f-u`, `pc_custom_spell_creation_rules`, `pc_magic_experimentation`, `ax_codex_and_scroll_magic`
- **Architecture docs:** `docs/spell_system_map.md` (maps spells to system hooks — load when building any system that spells interact with)
- **Depends on:** Characters (caster classes, spell repertoire)
- **Depended on by:** Combat (combat spells), Magic Research (campaign play), Treasure (scrolls, magic items)

### Equipment & Encumbrance
- **Rule files:** `acore_equipment`, `pc_equipment_catalog`
- **Depends on:** (none — foundational system)
- **Depended on by:** Characters (starting gear), Combat (weapons, armor), Exploration (encumbrance/movement), NPC Systems (wages, hiring)

### Proficiencies
- **Rule files:** `acore_proficiencies_rules_and_catalog`, `pc_proficiencies_catalog`, `ax_thief_skill_update`
- **Architecture docs:** `docs/proficiency_system_map.md` (maps proficiencies to system hooks — load when building any system that proficiencies interact with)
- **Depends on:** Characters (class proficiency lists)
- **Depended on by:** Characters (creation), Combat (combat proficiencies), Hijinks (skill throws), NPC Systems, Dungeon Exploration (thief-equivalent skills), Wilderness (tracking, navigation, survival), Domain Play (morale, construction), Spells & Magic (codex authority prerequisites)

### Monsters & Encounters
- **Rule files:**
  - Stats/creation: `le_monster_characteristics_stats`, `le_monster_creation`, `le_monster_parts`, `le_monster_training_rules`
  - ACKS Core catalogs: `acore_monster_catalog_a-dop`, `acore_monster_catalog_drag-gno`, `acore_monster_catalog_gol-lee`, `acore_monster_catalog_liz-orc`, `acore_monster_catalog_owl-sco`, `acore_monster_catalog_sea-tre`, `acore_monster_catalog_tri-wol`, `acore_monster_catalog_dragons`
  - L&E catalogs: `le_monster_catalog_1`, `le_monster_catalog_2_summary`, `le_monster_catalog_summary_3`, `le_monster_catalog_4`, `le_monster_catalog_5`, `le_monster_catalog_6`, `le_monster_catalog_7`, `le_monster_catalog_8_summary`, `le_monster_catalog_dragons`
  - Encounter procedures: `acore_adventures_and_encounters`, `acore-monster-stocking-rules`
- **GDDs:** `gdd-terrain-system` (encounter table selection)
- **Architecture docs:** `docs/monster_system_map.md` (monster ability hook map — load when building monster abilities or any system that consumes them)
- **Depends on:** Combat (monster stat blocks reference combat rules)
- **Depended on by:** All exploration contexts, Dungeon Stocking, Setting Generation, Domain Encounters

### Wilderness & Hex Exploration
- **Rule files:** `acore_adventures_and_encounters`, `acore-monster-stocking-rules`, `le_wilderness_lair_rules`
- **GDDs:** `gdd-terrain-system` (includes the wilderness hex generation/subdivision scope once tracked as `gdd-terrain-wilderness`), `gdd-setting-generation`, `gdd-poi-generation`, `gdd-weather-generation`, `gdd-combat-map-generation`, `gdd-realtime-scheduler`
- **Depends on:** Monsters & Encounters, Equipment (encumbrance -> movement rates), Weather (travel modifiers, visibility, foraging), Calendar & Seasons (daylight hours)
- **Depended on by:** Domain Play (territory classification), Setting Generation

### Urban & Settlement
- **Rule files:** `acore-setting-construction-rules`, `acore-campaign-hijinks`
- **GDDs:** `gdd-settlement-layout`, `gdd-settlement-stocking`, `gdd-name-generation`, `gdd-npc-personality`, `gdd-cultural-religious-generation`, `gdd-combat-map-generation`, `gdd-realtime-scheduler` (node-graph settlement model replaces walkable polygon-block maps from `gdd-settlement-layout`)
- **Depends on:** Equipment (market class, availability), Characters (hiring), Setting Generation (demographics)
- **Depended on by:** Domain Play (urban population), NPC Systems (settlement context)

### Settlement Stocking & Commerce
- **Rule files:** `acore_axioms_strongholds_and_domains`, `acore_equipment`, `acore_core_classes`, `acore_demihuman_classes`, `acore_campaign_classes`
- **GDDs:** `gdd-settlement-stocking`, `gdd-settlement-layout`, `gdd-npc-personality`, `gdd-cultural-religious-generation`, `gdd-name-generation`, `gdd-dungeon-factions`
- **Depends on:** Urban & Settlement, NPC Systems, Setting & World Generation
- **Depended on by:** Quest & Rumor System, Domain Play, UI & Presentation

### Dungeon Exploration
- **Rule files:** `acore_adventures_and_encounters`, `acore-setting-construction-rules`
- **GDDs:** `gdd-dungeon-layout`, `gdd-dungeon-factions`, `gdd-trap-generation`, `gdd-realtime-scheduler`
- **Depends on:** Monsters & Encounters, Combat, Equipment (light, tools), Spells (dungeon spells)
- **Depended on by:** Treasure (dungeon stocking populates treasure)

### Combat Maps & Tactical Terrain
- **Rule files:** `acore_combat_and_wounds`, `acore_adventures_and_encounters`, `ax_conditions_catalog`
- **GDDs:** `gdd-combat-map-generation`, `gdd-dungeon-layout`, `gdd-settlement-layout`, `gdd-stronghold-construction`, `gdd-terrain-system`, `gdd_combat_behavior_tags`
- **Depends on:** Combat & Conditions, Wilderness & Hex Exploration, Urban & Settlement, Domain Play
- **Depended on by:** Combat, Event Scheduler & Game Clock, UI & Presentation

### Event Scheduler & Game Clock
- **Rule files:** (none — project-designed system)
- **GDDs:** `gdd-realtime-scheduler`
- **Depends on:** Timekeeping (clock advancement, boundary signals), EventBus (signal dispatch), CampaignRepository (persistence), DiceSystem (encounter/detection rolls), Calendar & Seasons (dawn/dusk boundaries)
- **Depended on by:** Wilderness & Hex Exploration (travel legs, encounter checks, camping), Urban & Settlement (node-graph travel, activity scheduling), Dungeon Exploration (real-time movement, action queuing, wandering monster scheduling), Combat Maps & Tactical Terrain (combat entry/exit transitions), Domain Play (monthly resolution scheduling, construction completion, army movement), Campaign Play (long-duration activity scheduling), UI & Presentation (clock display, speed controls, entity outliner, notification feed)

### Domain Play (Strongholds, Realms, Population)
- **Rule files:** `acore_axioms_strongholds_and_domains`, `acore_stronghold_construction_costs.pdf` (cost / timeline / per-class follower table — added 2026-05-06), `daw_equipment_and_construction`, `ax_campaign_play`, `ax_domain_level_encounters`, `ax_domains_of_chaos`
- **GDDs:** `gdd-domain-tab`, `gdd-stronghold-construction`, `gdd-setting-generation` (demographics)
- **Implementation roadmap:** `docs/domain-roadmap-corrected.md` (10-phase build sequence; Phase 0 RAW-correctness landed 2026-05-06; Phase 1 stronghold construction landed 2026-05-06).
- **Phase 0 engine code:** `engine/subsystems/domains/` (revenue / expense / morale / growth / classification / land-improvement resolvers); rewrite of `engine/subsystems/session/handlers/domain_handlers.gd`; migrations 055-059 (`domain_hexes`, `domains` extensions, `domain_followers`, `ledger_entries`, `follower_arrivals`).
- **Phase 1 engine code:** `engine/subsystems/strongholds/` (`stronghold_cost_calculator`, `commission_pipeline`, `stronghold_repository`, `claiming_resolver`); migrations 060-062 (`strongholds`, `stronghold_commissions`, `stronghold_accessories`); data files `data/strongholds/structure_catalog.json` and `archetype_presets.json`; UI scaffolds `scenes/ui/strongholds/commission_wizard.tscn` and `claim_modal.tscn`. New event type `stronghold_construction_daily_tick` registered in `session_runner.gd`.
- **Depends on:** Characters (domain owner level/class), Wilderness (territory classification), Urban (settlements)
- **Depended on by:** Armies & Warfare, Campaign Play (monthly cycle)

### Armies & Warfare
- **Rule files:** `daw_armies_recruitment`, `daw_campaigning_armies`, `daw_campaigns_troop_tables_summary`, `daw_equipment_and_construction`, `daw_sieges`, `daw_vagaries`, `daw_axioms_pitching_battle`
- **Depends on:** Domain Play (garrison, population), Characters (commander), Equipment (military gear)
- **Depended on by:** (end-system — feeds narrative events back to domains)

### Treasure & Magic Items
- **Rule files:** `acore_treasure_and_magic_items_rules`
- **Depends on:** Monsters & Encounters (treasure types by monster)
- **Depended on by:** Equipment (found items enter inventory), Characters (XP from treasure)

### NPC Systems (Personality, Henchmen, Reactions)
- **Rule files:** `acore_equipment` (hirelings/henchmen costs), `pc_followers_tables_rules`, `ax_henchmen_recruitment_expanded`, `ax_reactions_and_influencing`, `ax_non_combatants`
- **GDDs:** `gdd-npc-personality`, `gdd-name-generation`, `gdd-henchman-class-selection`
- **Depends on:** Characters (CHA modifier, class), Equipment (wages), Proficiencies
- **Depended on by:** Party management, Domain Play (NPC rulers), Dungeon Factions (intelligent monsters)

### Campaign Play (Aging, Poisons, Research, Timekeeping)
- **Rule files:** `acore_aging_poisons_high-level-start_optional_rules`, `pc_aging_tables`, `acore-campaign-general-and-magic-research`, `ax_campaign_play`
- **GDDs:** `gdd-realtime-scheduler`
- **Depends on:** Characters (class, level), Spells & Magic (research prerequisites)
- **Depended on by:** Domain Play (monthly cycle), Event Scheduler & Game Clock

### Calendar & Seasons
- **Rule files:** (none — no ACKS sourcebook defines a calendar or seasonal system)
- **GDDs:** `gdd-calendar-seasons`
- **Depends on:** Setting Generation (hemisphere parameter from campaign creation)
- **Depended on by:** Weather, Domain Play (agricultural yield phases, seasonal trade), Timekeeping (daylight hours, day-cycle scheduling), Event Scheduler & Game Clock (dawn/dusk boundary events), LLM Context (seasonal narrative)

### Weather
- **Rule files:** `daw_vagaries` (severe weather conditions, DaW effects), `acore_adventures_and_encounters` (encounter distance/visibility, terrain movement multipliers, wind conditions for sea travel)
- **GDDs:** `gdd-weather-generation`
- **Depends on:** Calendar & Seasons (season lookup, solstice/equinox dates, transition blending), Setting Generation (Köppen climate codes per hex, effective latitude), Terrain (terrain tags for biome-specific weather profiles)
- **Depended on by:** Wilderness Exploration (travel speed, encounter distance, foraging modifiers), Domain Play (army supply costs, disease chance), Combat (visibility), Timekeeping (dawn/dusk times), LLM Context (weather descriptions)

### Wilderness Points of Interest
- **Rule files:** `acore-setting-construction-rules` (45-POI regional density target), `le_wilderness_lair_rules` (lair density — POI budget excludes lairs), `acore_adventures_and_encounters` (wilderness encounter tables by terrain)
- **GDDs:** `gdd-poi-generation`
- **Depends on:** Setting Generation (regional map, demographics), Terrain (terrain tags for affinity filtering), Culture & Religion (historical context for POI narrative), NPC Systems (rumor knowledge categories)
- **Depended on by:** Wilderness Exploration (discoverable locations), NPC Systems (rumor table seeds), Quest & Rumor System (quest hooks)

### Setting & World Generation
- **Rule files:** `acore-setting-construction-rules`, `acore-monster-stocking-rules`, `acore_axioms_strongholds_and_domains` (demographics)
- **GDDs:** `gdd-setting-generation`, `gdd-terrain-system`, `gdd-cultural-religious-generation`, `gdd-name-generation`, `gdd-poi-generation`, `gdd-calendar-seasons`, `gdd-weather-generation`
- **Depends on:** Monsters & Encounters, Domain Play (demographics)
- **Depended on by:** All exploration contexts, Urban & Settlement, Dungeon Exploration, Calendar & Seasons (hemisphere), Weather (climate codes)

### Quest & Rumor System
- **Rule files:** `acore-campaign-hijinks`, `ax_reactions_and_influencing`, `acore_adventures_and_encounters`, `acore_treasure_and_magic_items_rules`, `acore_axioms_strongholds_and_domains`
- **GDDs:** `gdd-quest-rumor-system`, `gdd-poi-generation`, `gdd-setting-generation`, `gdd-npc-personality`, `gdd-dungeon-layout`, `gdd-dungeon-factions`, `gdd-terrain-system`, `gdd-settlement-layout`, `gdd-cultural-religious-generation`
- **Depends on:** Wilderness Points of Interest, NPC Systems, Settlement Stocking & Commerce, Setting & World Generation
- **Depended on by:** Event Scheduler & Game Clock, Wilderness & Hex Exploration, Urban & Settlement

### UI & Presentation
- **Rule files:** (none directly — load the rule files for the subsystem a given screen presents)
- **GDDs:** `gdd-dungeon-map-ui`, `gdd-settlement-exploration-ui`, `gdd-combat-ui`, `gdd-realtime-scheduler`
- **Depends on:** All gameplay systems, Combat Maps & Tactical Terrain, Asset Architecture, Navigation Stack
- **Depended on by:** (end-system)

### Thief Skills & Hijinks (+ Syndicates / Hideouts)
- **Rule files:** `acore-campaign-hijinks`, `ax_thief_skill_update`
- **Thief→Syndicate decoupling (2026-06-03):** The three syndicate classes (thief / assassin / elven nightblade) do NOT run domains — they run a **syndicate** (thieves' guild) from a **hideout** planted inside someone else's settlement (RAW `ax_thief_skill_update`:50 "Hideouts are secret strongholds; do not secure domains"). For the initial release they may not create domains or domain-securing strongholds at all.
- **Engine code:** `engine/subsystems/syndicate/` — `found_syndicate_flow` (founding path, mirrors `EstablishDomainFlow`), `hideout_repository` + `hideout_cost_table` (RAW market-class cost/size), `syndicate_repository`, hijink resolvers, `npc_syndicate_monthly_resolver` (net L1-8 income + L9+ wage upkeep). Migration 143 (`hideouts` table + `syndicates.hideout_id`). Blocking lives in `establish_domain_flow` + `commission_pipeline` + `claiming_resolver` via `ClassBucketResolver.is_syndicate_class`. UI: `domain_tab_page` renders a syndicate surface (`found_syndicate_dialog` + `syndicate_block`) for these classes.
- **Depends on:** Characters (thief class + level ≥ 9 gate), Proficiencies (hijink throws), Urban context (host settlement market class → hideout cost + syndicate size cap), Commerce (`PartyWallet` for hideout funding + hijink/monthly income)
- **Depended on by:** Domain Play (the monthly tick resolves syndicates alongside domains, for domain-less bosses)

### Venturer / Guildhouse / Monopoly
- **Rule files:** `ax_venturer_class`, `ax_campaign_play` (mercantile activities)
- **Venturer→Guildhouse decoupling (2026-06-03):** The Venturer does NOT run a domain — it runs a **guildhouse** (a mercantile base that RAW says "follows hideout rules") in an urban settlement, plus an L12 **settlement monopoly** (1gp/urban-family/month, without ruling the domain). Blocked from domains/strongholds for the initial release.
- **Engine code:** `engine/subsystems/venturer/` — `found_guildhouse_flow` (founding + L12 `seize_monopoly`), `guildhouse_repository`, `venture_monthly_resolver` (monopoly revenue + apprentice wage upkeep). Migration 144 (`guildhouses` table; reuses `HideoutCostTable`). Blocking via `ClassBucketResolver.is_venturer_class` at the same three guard sites. **Apprentices are individual `followers` rows** (`source_kind='venturer_apprentice'`) — level-able, henchman-recruitable, future NPCs. UI: `domain_tab_page` renders a guildhouse surface (`found_guildhouse_dialog` + `guildhouse_block`).
- **Depends on:** Characters (venturer class + level gates 9/12), Followers/NPC roster (apprentices), Urban context (settlement market class + `urban_families`), Commerce (`PartyWallet`). NOTE: the L12 monopoly is DISTINCT from `monopoly_holdings`/`MonopolyRegistry` (the per-merchandise buy/sell trade advantage).
- **Depended on by:** Domain Play (the monthly tick resolves guildhouses alongside domains/syndicates)
- **Deferred:** the full Trade Block (buy/sell/trade-route activity launchers) — Phase 10B.2.

---

## File -> System Cross-Reference (High-Traffic Files)

Files appearing in 3+ systems — changes to these have wide blast radius:

| File | Systems |
|------|---------|
| `acore_basics_and_characters` | Characters, Combat (derived stats), all downstream systems |
| `acore_combat_and_wounds` | Combat, all exploration contexts, Monsters, Armies |
| `acore_adventures_and_encounters` | Wilderness, Dungeon, Monsters & Encounters, Setting Generation |
| `acore-setting-construction-rules` | Setting Generation, Urban & Settlement, Dungeon Exploration, Domain Play |
| `acore_equipment` | Equipment, Characters, NPC Systems (hiring/wages), Combat |
| `acore_axioms_strongholds_and_domains` | Domain Play, Setting Generation, Armies (garrison) |
| `ax_campaign_play` | Campaign Play, Domain Play (monthly cycle) |
| `daw_equipment_and_construction` | Armies & Warfare, Domain Play (stronghold costs) |
| `acore-monster-stocking-rules` | Monsters & Encounters, Wilderness, Setting Generation |
| `daw_vagaries` | Armies & Warfare, Weather |
| `le_wilderness_lair_rules` | Monsters & Encounters, Wilderness, Wilderness POI (budget exclusion) |

---

## GDD Dependency Graph

Generation documents and their inter-dependencies (arrow = "feeds into"):

```
gdd-terrain-system
  -> gdd-setting-generation
     -> gdd-dungeon-layout
        -> gdd-dungeon-factions
        -> gdd-trap-generation
     -> gdd-settlement-layout
        -> gdd-settlement-stocking
        -> gdd-stronghold-construction
     -> gdd-calendar-seasons
        -> gdd-weather-generation
     -> gdd-poi-generation
        -> gdd-quest-rumor-system

gdd-npc-personality
  -> gdd-name-generation
  -> gdd-settlement-stocking
  -> gdd-dungeon-factions
  -> gdd-henchman-class-selection
  -> gdd-quest-rumor-system

gdd-cultural-religious-generation
  -> gdd-settlement-stocking
  -> gdd-poi-generation
  -> gdd-henchman-class-selection
  -> gdd-quest-rumor-system

gdd_combat_behavior_tags
  -> gdd-combat-map-generation

gdd-stronghold-construction
  -> gdd-combat-map-generation

gdd-name-generation
  -> gdd-cultural-religious-generation

gdd-realtime-scheduler (cross-cuts all exploration, domain, and UI systems; blocks E-2)
  <- gdd-terrain-system (travel costs)
  <- gdd-setting-generation (hex data)
  <- gdd-calendar-seasons (boundary events)
  <- gdd-weather-generation (travel modifiers)
  <- gdd-dungeon-layout (diamond grid movement)
  <- gdd-settlement-layout (node graph source data — spatial model replaced per §4)
  <- gdd-combat-map-generation (combat transition)
  <- gdd_combat_behavior_tags (monster behavior in combat)
  <- gdd-poi-generation (overworld discoveries)
  <- gdd-dungeon-map-ui (dungeon interaction, fog of war, context menus)
  <- gdd-settlement-exploration-ui (settlement PoI navigation, travel calculator)
  <- gdd-combat-ui (turn-based combat UI, initiative, engagement, cleave)
gdd-proficiency-specializations (peripheral — augments Proficiencies system; feeds from setting/cultural generation; does not gate other GDDs)
```

**Implementation order suggestion** (respects dependencies):
1. `gdd-terrain-system` (foundational — no GDD dependencies)
2. `gdd-setting-generation` (needs terrain)
3. `gdd-dungeon-layout` (needs setting for context)
4. `gdd-settlement-layout` (needs setting, terrain)
5. `gdd-npc-personality` (feeds names, factions, rumors, and social generation)
6. `gdd-name-generation` (needs setting, settlement context, and NPC cultural identity)
7. `gdd-cultural-religious-generation` (needs setting, settlement context, and naming support)
8. `gdd-calendar-seasons` (needs setting for hemisphere parameter)
9. `gdd-weather-generation` (needs calendar/seasons, setting, terrain)
10. `gdd-poi-generation` (needs setting, terrain, and culture/religion context)
11. `gdd-settlement-stocking` (needs settlement layout, names, personalities, and culture data)
12. `gdd-dungeon-factions` (needs dungeon layout and NPC personality)
13. `gdd-trap-generation` (needs dungeon layout)
14. `gdd_combat_behavior_tags` (standalone combat AI support)
15. `gdd-stronghold-construction` (needs settlement and dungeon references)
16. `gdd-combat-map-generation` (needs terrain, tactical AI tags, and stronghold/dungeon/settlement context)
17. `gdd-realtime-scheduler` (needs terrain, calendar, weather, dungeon layout, settlement layout, combat maps; blocks E-2 session runner)
18. `gdd-quest-rumor-system` (needs POIs, settlement context, dungeon/faction context, and NPC/cultural data)
19. `gdd-henchman-class-selection` (needs NPC personality and culture/religion context)
20. `gdd-proficiency-specializations` (standalone; feeds from setting generation and monster training rules; can be implemented in parallel with any other GDD)
21. `gdd-dungeon-map-ui` (dungeon interaction — RTS selection, context menus, fog of war, control groups)
22. `gdd-settlement-exploration-ui` (settlement PoI navigation — menu-driven panel overlay, travel calculator)
23. `gdd-combat-ui` (turn-based combat UI — initiative, engagement, cleave, morale; shares grid with dungeon UI)
