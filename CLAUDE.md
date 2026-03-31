# ACKS Arbiter — Build Agent Instructions

You are the build agent for **ACKS Arbiter**, a sandbox RPG video game that functions as an autonomous Game Master for the Adventurer Conqueror King System (ACKS) First Edition. The project owner (Jedidiah) is a lawyer and game designer, not a programmer. He directs design; you implement.

## Core Principles

- **Build mechanically, narrate retroactively.** All game logic is deterministic. LLM is for narration only at runtime.
- **Engine-first, LLM-second.** Every system must work with mock/template provider before LLM integration.
- **Banker's rounding** (round half to even) everywhere. No exceptions.
- **Four combat progression types:** fighter, cleric, thief, mage. ("Crusader" is an ACKS II change, not present in ACSK 1e, "cleric" is both a class and the progression type.)
- **Three territory classifications:** Civilized, Borderlands, Wilderness. No "Outlands" or "Unsettled."
- **"Turn undead"** not "rebuke undead" per ACKS 1e conventions.

## Technology Stack

- **Engine:** Godot 4, GDScript only. No external frameworks.
- **Persistence:** SQLite via godot-sqlite GDExtension.
- **LLM at runtime:** Provider-agnostic service layer (cloud API, local model, or offline mock). Player configures via in-game setup wizard.
- **Platform:** Desktop (Windows, macOS, Linux via Godot export).

**Godot-specific constraints:**
- `class_name` declarations MUST NOT appear in autoload scripts (causes "hides an autoload singleton" error).
- godot-sqlite: `query(sql)` for no-param queries (returns bool); `query_with_bindings(sql, array)` for parameterized queries (returns bool); results in `db.query_result`; path uses `"user://"` not `"res://"`. **`query()` does NOT accept a second argument.**

---

## Document Authority — Three Layers

This project has three kinds of reference documents with different modification rules. Getting this wrong causes bugs.

### Layer 1: XML Rule Summaries (`rules/`)

**Authority: SACRED.** Extracted from published ACKS rulebooks.

- **You may NOT** change, "improve," or reinterpret any rule in these files.
- **You MUST** implement these rules faithfully in game code.
- **If a rule seems wrong:** Flag it with a comment, do not change the XML.
- **Source precedence (highest first):** Axioms → HFH excerpted → APC → L&E → DaW → ACore.

### Layer 2: Generation Design Documents (`generation/`)

**Authority: PROJECT-DESIGNED.** These fill gaps where ACKS is silent.

- **You MAY** suggest improvements, fix bugs, refactor algorithms, propose alternatives.
- **You MUST** respect any "ACKS Constraints" sections within each GDD — those parts come from the books.
- **If you think the approach is wrong:** Say so and propose a better one.

### Layer 3: Design Brief and Architecture (`docs/`)

**Authority: ARCHITECTURAL.** Defines how systems connect.

- **You may NOT** restructure interfaces, rename autoloads, change data models, or modify cross-system contracts without explicit approval from Jedidiah.
- **You MAY** implement within the defined architecture, add detail where the brief says "TBD," and flag architectural issues you discover.

---

## Project Directory Structure

```
C:\Users\jttau\acks-arbiter\
├── CLAUDE.md                    # This file (read every session)
├── build_log.md                 # Cross-session memory (read and update every session)
├── docs/
│   ├── acks_arbiter_design_brief_v11.md   # Architecture (read every session)
│   ├── document_map.md                     # File index (read every session, once created)
│   ├── rule_system_map.md                  # System dependencies (read every session, once created)
│   └── coding_conventions.md               # (consolidated here for reference)
├── rules/                        # XML rule summaries — NEVER MODIFY
│   ├── acore_*.xml
│   ├── pc_*.xml
│   ├── daw_*.xml
│   ├── le_*.xml
│   └── ax_*.xml
├── generation/                   # GDDs — modify freely
│   ├── gdd-*.md
│   ├── gdd-proficiency-specializations.md
│   └── combat_behavior_tags.md
├── engine/                       # Godot project (you build this)
├── data/                         # Runtime data files
└── test/                         # Test content and scenarios
```

---

## Build Session Protocol

Every session that modifies application code:

1. Read this file (`CLAUDE.md`).
2. Read `build_log.md` to understand current project state and what happened last session.
3. Read `docs/acks_arbiter_design_brief_v11.md`.
4. Read `docs/document_map.md` and `docs/rule_system_map.md` (when they exist).
5. Identify which XML rule summaries and GDDs are relevant to the current task. **Load only those files.** Never load the entire rules corpus.
6. If persistence is involved, inspect the current database schema.
7. If touching shared subsystem boundaries, inspect the relevant interface definitions.
8. Implement in Godot-native terms: scenes, nodes, resources, autoloads, signals, GDScript classes, SQLite-backed repositories.
9. Register any new actions in the action vocabulary definition file.
10. Run or update focused tests for the affected subsystem and any adjacent boundaries.
11. **Before ending the session**, update `build_log.md` (see below).

---

## Build Log — Cross-Session Memory

The file `build_log.md` at the project root is your memory across sessions. **Read it at the start of every session. Update it at the end of every session.**

### What to Record

At the end of each session, append an entry with:

```markdown
## Session [DATE] — [BRIEF TITLE]

**Task:** What was the goal this session.
**Model used:** Which model(s) for which phases.
**Completed:**
- What was built, changed, or fixed (specific files and functions).
**Decisions made:**
- Any architectural or design decisions, with rationale.
**Interfaces defined or changed:**
- Signal names, method signatures, data shapes that other subsystems depend on.
**Database changes:**
- Any migrations created or schema changes.
**Tests added/updated:**
- What's now tested that wasn't before.
**Known issues:**
- Bugs found but not fixed, edge cases deferred, things that need review.
**Next session should:**
- What to work on next, in priority order.
```

### Rules for the Build Log

- **Never delete old entries.** The log is append-only.
- **Be specific about interfaces.** If you defined a signal name, wrote a method signature, or created a data shape that other systems will depend on, write it down explicitly. This prevents naming drift across sessions.
- **Flag anything that needs Opus review.** If you're working on Sonnet and encounter something that needs deeper reasoning (complex rules interaction, architectural ambiguity), note it as `[NEEDS-OPUS-REVIEW]` in the log.

---

## Coding Conventions

### Naming

| Element | Convention | Example |
|---|---|---|
| GDScript classes / scene names | PascalCase | `CombatManager`, `HexMapRenderer` |
| GDScript files | snake_case | `combat_manager.gd`, `hex_map_renderer.gd` |
| Signals | Past-tense verbs, snake_case | `combat_started`, `inventory_updated` |
| Database tables | Plural snake_case | `characters`, `domains`, `encounters` |
| Resource files | Descriptive snake_case IDs | `terrain_forest_icon`, `token_pc_fighter` |
| Autoload singletons | PascalCase, truly global only | `GameState`, `CampaignRepository`, `LLMManager`, `AudioRouter` |
| Constants | SCREAMING_SNAKE_CASE | `MAX_PARTY_SIZE`, `COMBAT_ROUND_SECONDS` |
| Action vocabulary entries | snake_case verbs | `attack_melee`, `move_to_hex`, `cast_spell` |

## Coding Conventions Maintenance

The file `docs/coding_conventions.md` is a living document that grows as the project grows. **Review and update it when any of the following happen during a session:**

- You establish a new pattern that isn't documented (add it).
- You find yourself making a judgment call about style or structure that future sessions will face again (document the decision).
- You create a new autoload, signal pattern, database table pattern, or cross-subsystem interface (add the concrete example to the relevant section).
- You discover that a [PROVISIONAL] convention should be confirmed or changed based on actual implementation experience (update it and remove the tag).
- You encounter a convention that doesn't work in practice (flag it for Jedidiah's review, don't silently change it).

When updating, add the new content in the appropriate section — do not append a changelog at the bottom. The document should always read as a coherent reference, not a log. Note the date of significant changes in a one-line comment at the top of the affected section.

### Architecture Patterns

- **Autoloads** only for truly global systems. Do not proliferate autoloads.
- **Signals** for cross-system communication. Past-tense verb names.
- **Resources** for data that Godot's resource system handles well (configuration, templates).
- **SQLite** for all persistent game state. The database schema is ground truth.
- **Migrations** for schema changes. Sequential, versioned, never destructive.

### Testing

- Every subsystem gets focused unit tests.
- Cross-subsystem boundaries get integration tests.
- The entire game must work with the mock LLM provider.
- Test against hand-authored content before procedural generation.

### Error Handling

- Log all errors with context (what was attempted, what failed, what state).
- LLM validation failures: reject the action, log it, re-prompt if appropriate.
- Never silently swallow errors.

---

## Model Usage Guidelines

- **Use Sonnet for:** Implementation, test writing, data file conversion, boilerplate, routine edits. This is the default for 80% of work.
- **Switch to Opus for:** Planning sessions, ACKS rules interpretation, cross-subsystem integration design, architectural decisions, code review of complex subsystems. Use `/model opus` to switch.
- **Rule of thumb:** If the task requires reading multiple XML rule summaries and reasoning about how they interact, use Opus. If the task is "implement this plan in GDScript," use Sonnet.