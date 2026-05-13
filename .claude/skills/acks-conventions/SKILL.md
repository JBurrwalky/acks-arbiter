---
name: acks-conventions
description: Index, query, and check against the project's docs/coding_conventions.md — 3,000+ lines and 50+ numbered convention sections covering naming, signals, autoloads, SQLite, error handling, testing, action vocabulary, ACKS-specific implementation rules, and per-subsystem patterns. Use this skill BEFORE writing or modifying GDScript code in the ACKS Arbiter project — surface the conventions that apply to the task at hand, even ones you didn't think to look for. Use it BEFORE naming a signal, method, autoload, table, column, or constant — check whether a pattern is already established. Use it BEFORE making a cross-subsystem interface decision. Use it WHEN you find yourself about to write code that feels like a project-wide pattern — the chance it's already documented is high. Do NOT read the entire coding_conventions.md directly — the bundled script returns just the relevant sections, with adjacent-convention cross-references you might have missed.
---

# ACKS Arbiter Coding Conventions Navigator

## Why this skill exists

`docs/coding_conventions.md` is the living rulebook for GDScript style, signal patterns, autoload rules, SQLite usage, error handling, testing, action vocabulary, ACKS-specific implementation rules, and per-subsystem patterns across the project. It has grown to 3,000+ lines across 50+ numbered sections and continues to grow as new patterns emerge. The original protocol was to read the whole file at session start; at this size, that's wasteful and key conventions get skimmed.

This skill replaces the full-file read with **targeted retrieval plus proactive surfacing of adjacent conventions**. The "don't know to look for" failure mode is the real risk: a convention from §12 (ACKS-Specific Implementation Rules) is exactly what you need when working in §17 (Combat Subsystem), but you only thought to look at §17.

## When to use this skill

**Before writing code (highest leverage):**

- Before naming a signal, method, autoload, table, column, or constant: `lookup --search "<candidate name>"` to check whether a pattern is established.
- Before designing a new system or subsystem: `lookup --for-task "<task description>"` to surface every section that touches the task area.
- Before making a cross-subsystem interface decision: `lookup --section 11` (Cross-Subsystem Boundaries) and `lookup --search "<the other subsystem>"`.

**Mid-task:**

- When you're about to write something that smells like a pattern: search for it before inventing it.
- When unsure about banker's rounding, time granularity, dice conventions, or other ACKS-specific rules: `lookup --section 12` and `lookup --section 14` (ACKS Implementation Rules and Dice Conventions respectively).
- When a code review surfaces a convention question: search for the convention before re-deriving it.

**Periodically (for the project itself):**

- `lookup --lint` to surface drift: duplicate numbers, [PROVISIONAL] tags that have been around too long, sections without dates that probably need one.
- `lookup --toc` to scan the full section index when you've lost track of what's there.

**Proactively:**

The bundled `--for-task` mode is cheap insurance. Even when you think you know the relevant conventions, run it once at the start of any non-trivial coding task. The cost of *not* finding an applicable convention is inconsistent code, naming drift, or — worst case — rebuilding a pattern the project already has.

## How to use the bundled script

The script is at `scripts/conventions_lookup.py`. It auto-detects the conventions file at `<project-root>/docs/coding_conventions.md` relative to the script's location, or via `--path` override.

### Common commands

```bash
# Show the section index — section number + title + line range
python3 scripts/conventions_lookup.py --toc

# Show a specific section's full content
python3 scripts/conventions_lookup.py --section 12

# Search content across all sections (case-insensitive)
python3 scripts/conventions_lookup.py --search "banker"

# Rank sections by keyword overlap with a task description (don't-know-to-look mode)
python3 scripts/conventions_lookup.py --for-task "implement combat round resolver with initiative roll"

# Find sections containing a specific tag (e.g., [PROVISIONAL])
python3 scripts/conventions_lookup.py --tag "PROVISIONAL"

# Show the most recently added N sections (last in file order)
python3 scripts/conventions_lookup.py --last 5

# Lint — flag duplicate section numbers, structural drift, stale [PROVISIONAL] tags
python3 scripts/conventions_lookup.py --lint
```

### Output format

`--toc` and search/ranking commands return a list of section headers with line ranges:

```
§12. ACKS-Specific Implementation Rules                   [coding_conventions.md:1313-1378]
§14. Dice Conventions                                     [coding_conventions.md:1513-1528]
§19. Event Scheduler Conventions                          [coding_conventions.md:2012-2112]
```

`--section N` and `--last N` print full content. Use these only after `--toc` or `--search` narrowed to the relevant sections.

## Don't-know-to-look-for: the topical clusters

These are clusters of sections that frequently apply together. When a task touches one section in a cluster, the others are likely also relevant. The full topical-areas reference is in `references/convention_areas.md`.

| Task area | Primary section(s) | Often-also-relevant |
|---|---|---|
| Combat | §17 Combat | §10 Action Vocabulary, §12 ACKS Rules, §14 Dice, §53 Tactical Grid Voxel |
| New signal definition | §4 Signal Conventions | §11 Cross-Subsystem Boundaries |
| New SQLite table or migration | §6 SQLite Patterns | §1 Naming (column naming), §11 Cross-Subsystem |
| New autoload | §5 Autoload Rules | §1 Naming, §3 GDScript Style |
| Time / clock / scheduler | §19 Event Scheduler | §16 Session Runner, §12 ACKS Rules (time granularities), §27 Modal-from-scheduler |
| Wilderness / hex map | §53 Tactical Grid Voxel | §24 Fog of war, §25 Scheduler speed tables, §43-46 Phase 9C polish (terrain) |
| Domains / strongholds / armies | §29 Domain, §30 Stronghold, §34 Army Warfare | §31 Domain Tab UI, §33 Construction, §36 Realm AI, §38 Domain Encounters |
| Test writing | §9 Testing Patterns | §11 Cross-Subsystem (boundary tests) |
| Error handling | §8 Error Handling | §3 GDScript Style |

When in doubt, run `--for-task` with your task description and read the top 3-5 returned sections. It's almost always faster than skimming the TOC.

## Common drift the linter catches

The `--lint` command flags:

- Duplicate section numbers (none currently — the 2026-05-12 surgical cleanup put §13b at §53 and §42b at §54).
- `[PROVISIONAL]` tags older than 30 days (heuristic; manual judgment required to know if still provisional).
- Sections numbered ≥ 20 without a date suffix (newer convention pattern includes a date for provenance).
- Stray `## ` headers inside code fences (false positives in older tooling — script ignores by default but `--lint` notes them).

The linter is non-mutating — it reports only. Use its output to surface cleanup candidates.

## Updating the conventions file

When you add or modify a convention:

1. **Don't renumber existing sections.** Backward-incompatible to external references in `build_log.md` and elsewhere. Add new sections at the end of the file with the next available section number.
2. **Date your section.** New sections added since ~§20 carry a `(YYYY-MM-DD)` suffix. Continue this pattern.
3. **Tag new conventions `[PROVISIONAL]` until confirmed.** Per CLAUDE.md §"Coding Conventions Maintenance," provisional conventions get confirmed (or replaced) once implementation experience validates them.
4. **Cross-reference adjacent conventions inline** using `§N` notation. The script's `--search` finds these.

## What this skill does NOT do

- **Does not write code.** It surfaces conventions; you (or Claude Code) write the implementation.
- **Does not enforce conventions automatically.** A linter for convention adherence would be a separate skill or tool.
- **Does not replace `acks-build-log`.** Decisions and interface contracts live in the build log; style/structure rules live here. Both are worth consulting at session start.
- **Does not modify `docs/coding_conventions.md` content** — only renumbering / structural fixes done with explicit approval. Convention authoring is human work.

## Bundled resources

- `scripts/conventions_lookup.py` — the query tool. Stdlib only. Auto-detects `<project>/docs/coding_conventions.md`.
- `references/convention_areas.md` — the topical clusters cheat sheet, expanded with example task → applicable sections mappings.
