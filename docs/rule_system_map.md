# Rule System Map

Maps game systems to their source files and cross-dependencies.
Read this every session to understand which systems are affected by your current task.

## How to Use

When working on system X:
1. Load the XML files listed under that system
2. Check **Depends on** for upstream systems that may constrain your work
3. Check **Depended on by** for downstream systems you might break
4. Load relevant GDDs if doing generation work

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
- **Depends on:** Combat (monster stat blocks reference combat rules)
- **Depended on by:** All exploration contexts, Dungeon Stocking, Setting Generation, Domain Encounters

### Wilderness & Hex Exploration
- **Rule files:** `acore_adventures_and_encounters`, `acore-monster-stocking-rules`, `le_wilderness_lair_rules`
- **GDDs:** `gdd-terrain-system`, `gdd-setting-generation`, `gdd-poi-generation`, `gdd-weather-generation`
- **Depends on:** Monsters & Encounters, Equipment (encumbrance -> movement rates), Weather (travel modifiers, visibility, foraging), Calendar & Seasons (daylight hours)
- **Depended on by:** Domain Play (territory classification), Setting Generation

### Urban & Settlement
- **Rule files:** `acore-setting-construction-rules`, `acore-campaign-hijinks`
- **GDDs:** `gdd-settlement-layout`, `gdd-npc-personality`, `gdd-cultural-religious-generation`
- **Depends on:** Equipment (market class, availability), Characters (hiring), Setting Generation (demographics)
- **Depended on by:** Domain Play (urban population), NPC Systems (settlement context)

### Dungeon Exploration
- **Rule files:** `acore_adventures_and_encounters`, `acore-setting-construction-rules`
- **GDDs:** `gdd-dungeon-layout`, `gdd-dungeon-factions`, `gdd-trap-generation`
- **Depends on:** Monsters & Encounters, Combat, Equipment (light, tools), Spells (dungeon spells)
- **Depended on by:** Treasure (dungeon stocking populates treasure)

### Domain Play (Strongholds, Realms, Population)
- **Rule files:** `acore_axioms_strongholds_and_domains`, `daw_equipment_and_construction`, `ax_campaign_play`, `ax_domain_level_encounters`, `ax_domains_of_chaos`
- **GDDs:** `gdd-stronghold-construction`, `gdd-setting-generation` (demographics)
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
- **GDDs:** `gdd-npc-personality`, `gdd-henchman-class-selection`
- **Depends on:** Characters (CHA modifier, class), Equipment (wages), Proficiencies
- **Depended on by:** Party management, Domain Play (NPC rulers), Dungeon Factions (intelligent monsters)

### Campaign Play (Aging, Poisons, Research, Timekeeping)
- **Rule files:** `acore_aging_poisons_high-level-start_optional_rules`, `pc_aging_tables`, `acore-campaign-general-and-magic-research`, `ax_campaign_play`
- **Depends on:** Characters (class, level), Spells & Magic (research prerequisites)
- **Depended on by:** Domain Play (monthly cycle), Session Runner (timekeeping)

### Calendar & Seasons
- **Rule files:** (none — no ACKS sourcebook defines a calendar or seasonal system)
- **GDDs:** `gdd-calendar-seasons`
- **Depends on:** Setting Generation (hemisphere parameter from campaign creation)
- **Depended on by:** Weather, Domain Play (agricultural yield phases, seasonal trade), Timekeeping (daylight hours, day-cycle scheduling), LLM Context (seasonal narrative)

### Weather
- **Rule files:** `daw_vagaries` (severe weather conditions, DaW effects), `acore_adventures_and_encounters` (encounter distance/visibility, terrain movement multipliers, wind conditions for sea travel)
- **GDDs:** `gdd-weather-generation`
- **Depends on:** Calendar & Seasons (season lookup, solstice/equinox dates, transition blending), Setting Generation (Köppen climate codes per hex, effective latitude), Terrain (terrain tags for biome-specific weather profiles)
- **Depended on by:** Wilderness Exploration (travel speed, encounter distance, foraging modifiers), Domain Play (army supply costs, disease chance), Combat (visibility), Timekeeping (dawn/dusk times), LLM Context (weather descriptions)

### Wilderness Points of Interest
- **Rule files:** `acore-setting-construction-rules` (45-POI regional density target), `le_wilderness_lair_rules` (lair density — POI budget excludes lairs), `acore_adventures_and_encounters` (wilderness encounter tables by terrain)
- **GDDs:** `gdd-poi-generation`
- **Depends on:** Setting Generation (regional map, demographics), Terrain (terrain tags for affinity filtering), Culture & Religion (historical context for POI narrative), NPC Systems (rumor knowledge categories)
- **Depended on by:** Wilderness Exploration (discoverable locations), NPC Systems (rumor table seeds), Quest/Rumor System (quest hooks)

### Setting & World Generation
- **Rule files:** `acore-setting-construction-rules`, `acore-monster-stocking-rules`, `acore_axioms_strongholds_and_domains` (demographics)
- **GDDs:** `gdd-setting-generation`, `gdd-terrain-system`, `gdd-cultural-religious-generation`, `gdd-poi-generation`, `gdd-calendar-seasons`, `gdd-weather-generation`
- **Depends on:** Monsters & Encounters, Domain Play (demographics)
- **Depended on by:** All exploration contexts, Urban & Settlement, Dungeon Exploration, Calendar & Seasons (hemisphere), Weather (climate codes)

### Thief Skills & Hijinks
- **Rule files:** `acore-campaign-hijinks`, `ax_thief_skill_update`
- **Depends on:** Characters (thief class), Proficiencies, Urban context (settlement market class)
- **Depended on by:** (end-system)

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
     -> gdd-settlement-layout
        -> gdd-stronghold-construction
     -> gdd-cultural-religious-generation
        -> gdd-henchman-class-selection
     -> gdd-dungeon-layout
        -> gdd-dungeon-factions
        -> gdd-trap-generation
     -> gdd-calendar-seasons
        -> gdd-weather-generation
     -> gdd-poi-generation

gdd-npc-personality (cross-cuts: settlement, dungeon factions, henchman selection, POI generation)
gdd-proficiency-specializations (peripheral — augments Proficiencies system; feeds from setting/cultural generation; does not gate other GDDs)
gdd_combat_behavior_tags (standalone — used by combat subsystem only)
```

**Implementation order suggestion** (respects dependencies):
1. `gdd-terrain-system` (foundational — no GDD dependencies)
2. `gdd_combat_behavior_tags` (standalone)
3. `gdd-setting-generation` (needs terrain)
4. `gdd-calendar-seasons` (needs setting for hemisphere parameter)
5. `gdd-weather-generation` (needs calendar/seasons, setting, terrain)
6. `gdd-dungeon-layout` (needs setting for context)
7. `gdd-npc-personality` (needs setting, settlement)
8. `gdd-settlement-layout` (needs setting, terrain)
9. `gdd-cultural-religious-generation` (needs setting, NPC personality)
10. `gdd-poi-generation` (needs setting, terrain, culture/religion, NPC personality)
11. `gdd-dungeon-factions` (needs dungeon layout, NPC personality)
12. `gdd-trap-generation` (needs dungeon layout)
13. `gdd-stronghold-construction` (needs settlement, dungeon layout)
14. `gdd-henchman-class-selection` (needs NPC personality, culture/religion)
15. `gdd-proficiency-specializations` (standalone; feeds from setting generation and monster training rules; can be implemented in parallel with any other GDD)
