# ACKS Arbiter — Build Log

This file is the project's cross-session memory. Claude Code reads it at the start of every session and appends an entry at the end. **Never delete old entries.**

---

## Session 2026-03-25 — Project Initialization

**Task:** Set up project directory structure and build agent configuration.
**Completed:**
- Created CLAUDE.md with full build agent instructions.
- Created build_log.md (this file).
- Project files are currently flat in root. First Claude Code task is to reorganize into `rules/`, `generation/`, `docs/` structure.
**Decisions made:**
- Build agent is Claude Code only (no OpenClaw, no Ollama). Rationale: simpler toolchain, better code quality, lower cost, purpose-built for coding tasks.
- Default model: Sonnet 4.6 for implementation, Opus 4.6 for planning/review.
- Cross-session memory via this build_log.md file rather than a persistent agent daemon.
- Design brief v11 replaces all prior versions. The old rule atom JSON system is fully abandoned; XML rule summaries and GDDs are the authoritative build sources.
**Next session should:**
1. Reorganize files into directory structure (first task in CLAUDE.md).
2. Create the document map (`docs/document_map.md`) — index all XML and GDD files.
3. Create the rule system map (`docs/rule_system_map.md`) — system dependencies and cross-references.

---

## Session 2026-03-25 — Project Reorganization

**Task:** Execute First Task from CLAUDE.md — reorganize files into correct directory structure.
**Model used:** Sonnet 4.6
**Completed:**
- Verified existing state: `rules/`, `generation/`, `docs/` directories and their contents were already correctly placed from prior work.
- `rules/` contains 63 XML rule summary files (acore_*, ax_*, daw_*, le_*, pc_*).
- `generation/` contains 11 GDD files (gdd-*.md + gdd_combat_behavior_tags.md).
- `docs/` contains `acks_arbiter_design_brief_v11.md`.
- Created missing directories: `engine/`, `data/`, `test/` (each with `.gitkeep` placeholder).
- Committed CLAUDE.md, build_log.md, and the three new directories: commit `0314b11`.
- Note: `document_authority_architecture.md` and `coding_conventions.md` referenced in CLAUDE.md do not exist yet — not a problem, they are listed as optional/future.
**Decisions made:**
- Used `.gitkeep` files to allow git to track empty `engine/`, `data/`, `test/` directories.
**Known issues:**
- `docs/document_map.md` and `docs/rule_system_map.md` do not exist yet (listed as "once created" in CLAUDE.md — not blocking).
- `document_authority_architecture.md` listed in CLAUDE.md reorganization steps does not exist in repo — may have been superseded before creation.
**Next session should:**
1. Create `docs/document_map.md` — index all 63 XML rule files and 11 GDDs with brief descriptions.
2. Create `docs/rule_system_map.md` — map game systems to their rule file dependencies.
3. Begin engine implementation per the design brief.

## Session 2026-03-25 — document map and rule system map planning

**Task:** Create the docs/document_map.md and docs/rule_system_map.md files according to the specs in CLAUDE.md and \docs\acks_arbiter_design_brief_v11.md". These need to be very well crafted as they will guide the rest of the project. Come up with a good plan for what they should contain based on the CLAUDE.md file instructions and the Design Brief document in /docs and present your plan for what they will look like to me for approval.

**Model Used:** Opus 4.6 - Max Effort

**Completed:** Completed the Planning Phase. The plan was as follows:
 Summary

  docs/document_map.md — A tabular index of all 63 XML rule files and 11 GDDs. Organized by source book (acore_, pc_,
  daw_, le_, ax_), with each file getting a one-line content summary and key topic keywords. Purpose: fast lookup when
  the agent needs to find which files to load for a task.

  docs/rule_system_map.md — An inverse index organized by game system (Combat, Characters, Domains, etc.), listing which
   XML files and GDDs each system needs, plus explicit "depends on" / "depended on by" relationships. Includes a
  high-traffic file cross-reference for blast radius awareness. Purpose: impact analysis and dependency tracking when
  implementing or modifying a subsystem.

  Key design decisions in the plan:

  - Table format for document_map (compact, scannable)
  - Bullet-list format for rule_system_map (structured but not prose-heavy)
  - 15 game systems identified as the taxonomy for rule_system_map
  - Only existing files indexed (the design brief references some GDDs that don't exist yet like gdd-name-generation.md
  — these would be noted separately)
  - High-traffic files section at the end of rule_system_map flags XML files used by 3+ systems (changing these has wide
   blast radius)

  The full plan with proposed structures is in the plan file. One note: I'll verify every file description by reading
  the actual XML/GDD headers during implementation, not just relying on the explorer's summaries.

● User approved Claude's plan
  ⎿  Plan saved to: ~\.claude\plans\peaceful-growing-crystal.md · /plan to edit
     Plan: Create document_map.md and rule_system_map.md

     Context

     These two files are referenced in CLAUDE.md as part of the Build Session Protocol (step 4) — they are read at the
     start of every build session. Their purpose is to let the build agent quickly identify which XML rule summaries and
      GDDs are relevant to the current task (step 5: "Load only those files. Never load the entire rules corpus."). They
      need to be well-crafted because they'll guide every future implementation session.

     The project currently has:
     - 63 XML rule files in rules/ (sacred, from ACKS rulebooks)
     - 11 GDD files in generation/ (project-designed, modifiable)
     - 1 design brief in docs/ (architectural)

     ---
     File 1: docs/document_map.md — File Index

     Purpose: Quick-reference index so the build agent knows what every file contains and can select the right ones for
     any task.

     Design principles:
     - Table format for fast scanning (one row per file)
     - Organized by source book (matching file prefixes: acore_, pc_, daw_, le_, ax_)
     - Each file gets: filename, one-line content summary, key topics/keywords for search
     - GDDs in a separate section with status and dependency callouts
     - Must fit in a single read without scrolling forever — concise descriptions only

     Proposed structure:

     # Document Map

     Quick-reference index of all rule summaries and design documents.
     Read this every session to identify which files to load for your current task.

     ## Source Precedence (highest first)
     Axioms (ax_) > HFH excerpted > Player's Companion (pc_) > Lairs & Encounters (le_) > Domains at War (daw_) > ACKS
     Core (acore_)

     ## Rules — ACKS Core (acore_*)
     [TABLE: File | Contents | Key Topics]
     26 rows covering: basics/characters, classes (core, demihuman, campaign), equipment,
     proficiencies, spellcaster rules, spell catalogs (A-I, K-W), combat, adventures/encounters,
     treasure/magic items, optional rules, strongholds/domains, setting construction,
     monster stocking, campaign play, hijinks, monster catalogs (7 alphabetical splits + dragons)

     ## Rules — Player's Companion (pc_*)
     [TABLE: File | Contents | Key Topics]
     9 rows covering: classes (4 files), equipment, proficiencies, followers,
     aging, custom spells, magic experimentation, spell catalogs (A-E, F-U)

     ## Rules — Domains at War (daw_*)
     [TABLE: File | Contents | Key Topics]
     7 rows covering: recruitment, campaigning, troop tables, equipment/construction,
     sieges, vagaries, pitched battle

     ## Rules — Lairs & Encounters (le_*)
     [TABLE: File | Contents | Key Topics]
     8 rows covering: monster characteristics, creation, parts, training,
     wilderness lairs, monster catalogs (7 files + dragons)

     ## Rules — Axioms Magazine (ax_*)
     [TABLE: File | Contents | Key Topics]
     10 rows covering: campaign play, codex/scroll magic, conditions, domain encounters,
     domains of chaos, henchman recruitment, mortal wounds, non-combatants,
     reactions/influencing, thief skills, venturer class

     ## Generation Design Documents (gdd-*)
     [TABLE: File | Contents | Status | Key Dependencies]
     11 rows covering all GDDs, each with its XML file dependencies listed

     ## Architecture Documents (docs/)
     Brief listing of design brief, this file, rule_system_map.md, coding_conventions.md

     ---
     File 2: docs/rule_system_map.md — System Dependencies

     Purpose: When working on a specific game system, tells the agent exactly which files provide the rules, which GDDs
     handle generation, and which other systems are connected. Prevents missing dependencies and enables impact
     analysis.

     Design principles:
     - Organized by game system (not by file) — this is the inverse of document_map
     - Each system section lists: rule files needed, GDDs involved, depends-on, depended-on-by
     - Includes a cross-reference matrix showing which systems share files
     - Compact format — bullet lists, not prose

     Proposed structure:

     # Rule System Map

     Maps game systems to their source files and cross-dependencies.
     Read this every session to understand which systems are affected by your current task.

     ## How to Use
     When working on system X:
     1. Load the XML files listed under that system
     2. Check "Depends on" for upstream systems that may constrain your work
     3. Check "Depended on by" for downstream systems you might break
     4. Load relevant GDDs if doing generation work

     ## Systems

     ### Character Creation & Classes
     - **Rule files:** acore_basics_and_characters, acore_core_classes, acore_demihuman_classes,
       acore_campaign_classes, pc_classes_1-4, ax_venturer_class
     - **GDDs:** gdd-henchman-class-selection (for henchman 0th→1st level)
     - **Depends on:** Proficiencies, Equipment
     - **Depended on by:** Combat, Magic, Domain Play, NPC Systems

     ### Combat & Conditions
     - **Rule files:** acore_combat_and_wounds, ax_conditions_catalog, ax_mortal_wounds_and_tampering
     - **GDDs:** gdd_combat_behavior_tags
     - **Depends on:** Characters, Equipment, Spells, Monsters
     - **Depended on by:** All exploration contexts (wilderness, dungeon, urban, sea)

     ### Spells & Magic
     - **Rule files:** acore_spellcaster_rules, acore_spell_catalog_a-i, acore_spell_catalog_k-w,
       pc_spell_catalog_a-e, pc_spell_catalog_f-u, pc_custom_spell_creation_rules,
       pc_magic_experimentation, ax_codex_and_scroll_magic
     - **Depends on:** Characters (caster classes)
     - **Depended on by:** Combat, Magic Research (campaign play)

     ### Equipment & Encumbrance
     - **Rule files:** acore_equipment, pc_equipment_catalog
     - **Depends on:** (none — foundational)
     - **Depended on by:** Characters, Combat, Exploration

     ### Proficiencies
     - **Rule files:** acore_proficiencies_rules_and_catalog, pc_proficiencies_catalog
     - **Depends on:** Characters (class proficiency lists)
     - **Depended on by:** Characters, Combat, Hijinks, NPC Systems

     ### Monsters & Encounters
     - **Rule files:** acore_monster_catalog_* (7 files), acore_monster_catalog_dragons,
       le_monster_catalog_* (7 files), le_monster_catalog_dragons,
       le_monster_characteristics_stats, le_monster_creation, le_monster_parts,
       le_monster_training_rules, acore_adventures_and_encounters,
       acore-monster-stocking-rules
     - **GDDs:** gdd-terrain-system (encounter table selection)
     - **Depends on:** Combat (monster stat blocks reference combat rules)
     - **Depended on by:** All exploration contexts, Dungeon Stocking, Setting Generation

     ### Wilderness & Hex Exploration
     - **Rule files:** acore_adventures_and_encounters, acore-monster-stocking-rules
     - **GDDs:** gdd-terrain-system, gdd-setting-generation
     - **Depends on:** Monsters & Encounters, Equipment (encumbrance → movement)
     - **Depended on by:** Domain Play (territory classification)

     ### Urban & Settlement
     - **Rule files:** acore-setting-construction-rules, acore-campaign-hijinks
     - **GDDs:** gdd-settlement-layout, gdd-settlement-stocking, gdd-npc-personality
     - **Depends on:** Equipment (market class), Characters (hiring)
     - **Depended on by:** Domain Play (urban population)

     ### Dungeon Exploration
     - **Rule files:** acore_adventures_and_encounters, acore-setting-construction-rules
     - **GDDs:** gdd-dungeon-layout, gdd-dungeon-factions, gdd-trap-generation
     - **Depends on:** Monsters & Encounters, Combat, Equipment (light sources, tools)
     - **Depended on by:** Treasure (dungeon stocking populates treasure)

     ### Domain Play (Strongholds, Realms, Population)
     - **Rule files:** acore_axioms_strongholds_and_domains, daw_equipment_and_construction,
       ax_domain_level_encounters, ax_domains_of_chaos
     - **GDDs:** gdd-stronghold-construction, gdd-setting-generation (demographics)
     - **Depends on:** Characters (domain owner), Wilderness (territory class), Urban (settlement)
     - **Depended on by:** Armies & Warfare

     ### Armies & Warfare
     - **Rule files:** daw_armies_recruitment, daw_campaigning_armies, daw_campaigns_troop_tables_summary,
       daw_equipment_and_construction, daw_sieges, daw_vagaries, daw_axioms_pitching_battle
     - **Depends on:** Domain Play (garrison, population), Characters (commander), Equipment (military)
     - **Depended on by:** (end-system — feeds narrative events back to domains)

     ### Treasure & Magic Items
     - **Rule files:** acore_treasure_and_magic_items_rules
     - **Depends on:** Monsters & Encounters (treasure types by monster)
     - **Depended on by:** Equipment (found items), Characters (XP from treasure)

     ### NPC Systems (Personality, Henchmen, Reactions)
     - **Rule files:** acore_equipment (hirelings/henchmen), pc_followers_tables_rules,
       ax_henchmen_recruitment_expanded, ax_reactions_and_influencing, ax_non_combatants
     - **GDDs:** gdd-npc-personality, gdd-henchman-class-selection
     - **Depends on:** Characters (CHA modifier, class), Equipment (wages)
     - **Depended on by:** Party management, Domain Play (NPC rulers)

     ### Campaign Play (Aging, Poisons, Research, Timekeeping)
     - **Rule files:** acore_aging_poisons_high-level-start_optional_rules, pc_aging_tables,
       acore-campaign-general-and-magic-research, ax_campaign_play
     - **Depends on:** Characters, Spells & Magic
     - **Depended on by:** Domain Play (monthly cycle), Session Runner (timekeeping)

     ### Setting & World Generation
     - **Rule files:** acore-setting-construction-rules, acore-monster-stocking-rules,
       acore_axioms_strongholds_and_domains (demographics)
     - **GDDs:** gdd-setting-generation, gdd-terrain-system
     - **Depends on:** Monsters & Encounters, Domain Play (demographics)
     - **Depended on by:** All exploration contexts, Settlements, Dungeons

     ### Thief Skills & Hijinks
     - **Rule files:** acore-campaign-hijinks, ax_thief_skill_update
     - **Depends on:** Characters (thief class), Proficiencies, Urban context
     - **Depended on by:** (end-system)

     ## File → System Cross-Reference (Selected High-Traffic Files)

     Files that appear in 3+ systems — changing these has wide blast radius:
     - `acore_basics_and_characters.xml` → Characters, Combat, all derived systems
     - `acore_combat_and_wounds.xml` → Combat, all exploration contexts, Monsters
     - `acore_adventures_and_encounters.xml` → Wilderness, Dungeon, Monsters, Encounters
     - `acore-setting-construction-rules.xml` → Settings, Settlements, Dungeons, Domains
     - `acore_equipment.xml` → Equipment, Characters, NPC hiring, Encumbrance
     - `acore_axioms_strongholds_and_domains.xml` → Domains, Setting Generation, Armies

     ---
     Verification

     After creating both files:
     1. Confirm every XML file in rules/ appears in document_map.md (count = 63)
     2. Confirm every GDD in generation/ appears in document_map.md (count = 11)
     3. Confirm every XML file appears in at least one system in rule_system_map.md
     4. Confirm no circular "depends on" chains (there shouldn't be — these are rule dependencies, not code
     dependencies)
     5. Cross-check GDD dependency lists against the GDD files themselves (each GDD names its own dependencies)

     ---
     Implementation Steps

     1. Read every XML file's first 10-20 lines to verify content descriptions are accurate
     2. Read every GDD file's header/dependency section to verify dependency lists
     3. Write docs/document_map.md with accurate per-file descriptions
     4. Write docs/rule_system_map.md with verified system-to-file mappings
     5. Run verification checks above
     6. Commit both files
**Known issues:** Claude servers hit major outages mid-task. Creation of the files never took place.

**Next Session:**
1. Create `docs/document_map.md` — index all 63 XML rule files and 11 GDDs with brief descriptions.
2. Create `docs/rule_system_map.md` — map game systems to their rule file dependencies.
3. Create `docs/coding_conventions.md` maintain consistent coding conventions across sessions.