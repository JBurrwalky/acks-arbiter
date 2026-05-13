---
name: acks-build-log
description: Index, query, and append entries to the project's build_log.md — 21,000+ lines of session-by-session memory across 260+ build sessions. Use this skill at the START of every build session to retrieve the most recent entry, surface prior decisions on the current task's topic, and check for outstanding [NEEDS-OPUS-REVIEW] flags. Use it MID-SESSION whenever you need to recall an interface contract, a signal name, a method signature, a database schema decision, or whether something has been attempted before. Use it at SESSION END to format and verify a new entry against the project's template. Use it PROACTIVELY whenever a task touches a system with prior history — the bundled script surfaces relevant past sessions even when you didn't think to ask. Do NOT read the full build_log.md directly — at 21,000+ lines it is too large for routine consultation. This skill supersedes the CLAUDE.md mandate to read the whole log at session start; instead, follow the procedure below to pull only what's relevant.
---

# ACKS Arbiter Build Log Navigator

## Why this skill exists

`build_log.md` is the project's cross-session memory: every build session leaves an entry recording task, decisions, interface contracts, database changes, known issues, and what the next session should do. It has grown to 21,000+ lines across 260+ sessions and continues to grow daily. Reading the whole file every session was the original protocol, but at this size:

- Most content is irrelevant to any given session.
- Important interface contracts, signal names, and method signatures get buried.
- `[NEEDS-OPUS-REVIEW]` flags from prior sessions are easy to miss.
- The "you may not know to look for X" problem is real: a fix from session 87 is exactly what's needed in session 263, but nobody remembers session 87 exists.

This skill replaces full-file reads with targeted queries. Smaller token cost, better recall.

## When to use this skill

**At session start (required for any non-trivial build session):**

1. Run `lookup --last 1` to see the most recent entry.
2. Run `lookup --next-actions 3` to see what the last few sessions said the next session should do.
3. Run `lookup --needs-review` to see outstanding `[NEEDS-OPUS-REVIEW]` flags.
4. If today's task touches an existing system, run `lookup --for-task "<task description>"` to surface the 3-5 most relevant prior sessions.

**Mid-session:**

- Before naming a signal, method, autoload, or table: `lookup --search "<candidate name>"` to check whether it already exists or was discussed.
- Before defining an interface (signal payload shape, method signature, repository function): `lookup --interface "<name>"` to find prior decisions.
- When making an architectural decision that smells like one you've made before: `lookup --search "<topic>"` to find the prior decision and its rationale.
- When you find a bug: `lookup --search "<bug-related-keyword>"` — it may have been encountered or fixed before.

**At session end:**

- Use `references/entry_template.md` as the canonical entry shape.
- Run `lookup --lint` after appending to flag fields that don't match the project template (capitalization drift, missing fields).
- Confirm `[NEEDS-OPUS-REVIEW]` tags are used for genuine handoff items, not as catchalls.

**Proactively:**

The build log records 260+ sessions of decisions. Even when you don't think there's prior history, a quick `lookup --for-task` is cheap insurance. The cost of *not* finding a prior decision is wasted re-deriving it, or worse, contradicting it.

## How to use the bundled script

The script is at `scripts/build_log_index.py`. It auto-detects the build log at `<project-root>/build_log.md` relative to the script's location, or via `--log-path` override.

### Common commands

```bash
# Show the most recent entry
python3 scripts/build_log_index.py --last

# Show the last 3 entries
python3 scripts/build_log_index.py --last 3

# Table of contents — every session date + title + line range
python3 scripts/build_log_index.py --toc

# Find sessions mentioning a keyword (case-insensitive substring across whole entries)
python3 scripts/build_log_index.py --search "EventScheduler"

# Find entries whose **Interfaces defined or changed:** field mentions a name
python3 scripts/build_log_index.py --interface "combat_ended"

# Find all entries containing [NEEDS-OPUS-REVIEW]
python3 scripts/build_log_index.py --needs-review

# Collect "Next session should:" notes from recent entries
python3 scripts/build_log_index.py --next-actions 5

# Find sessions since a date
python3 scripts/build_log_index.py --since 2026-05-01

# Suggest sessions relevant to today's task
python3 scripts/build_log_index.py --for-task "implement settlement market price drift"

# Show a specific entry by its starting line number
python3 scripts/build_log_index.py --id 8012

# Flag entries that don't follow the standard template
python3 scripts/build_log_index.py --lint
```

### Output format

Most commands return a list of session matches in this form:

```
2026-05-12 — Phase 10B-prereq Mercantile GDD + Prereq.1 (Merchandise Registry)  [build_log.md:21188-21280]
2026-05-11 — Mercantile handoff: Q-MERC-1A resolved...                          [build_log.md:21122-21154]
...
```

The line range lets you `Read` the full entry on demand. The TOC is meant to be skimmed; specific entries are read only when relevant.

`--last` and `--id` print full entry content. Everything else prints a list for the calling Claude to triage.

## Session entry template

The canonical entry shape — match this when appending. The full template with field-by-field guidance is in `references/entry_template.md`.

```markdown
## Session YYYY-MM-DD — Brief Title

**Task:** What was the goal this session.
**Model used:** Which model(s) for which phases. (e.g., "Sonnet 4.6 implementation, Opus 4.6 for the RAW verification pass")
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

**Capitalization matters.** Use `Model used:` (not `Model Used:`) and `Next session should:` (not `Next Session:`). The script's `--lint` mode flags drift; the indexer's field-matching is case-insensitive but the project's conventions are consistent capitalization.

**Use `[NEEDS-OPUS-REVIEW]` inline** in any field where Sonnet hit something that needs deeper reasoning. The `--needs-review` query finds these.

## What this skill does NOT do

- **Does not delete or modify old entries.** The log is append-only per CLAUDE.md. The script reads but does not write to the log.
- **Does not summarize the project's state.** It surfaces session entries; building a current-state-of-interfaces document is separate work.
- **Does not replace `acks-raw-lookup`.** RAW citations go through the rules corpus, not the build log.
- **Does not replace `acks-conventions`** (when that skill is built). Coding conventions live in `docs/coding_conventions.md`, not in the build log.

## Don't-know-to-look-for guidance

The hardest failure mode in a 260-session log is the prior decision that's exactly relevant but uses different vocabulary than today's task. Three habits that help:

1. **Search synonyms.** If you're working on "movement," also search "travel," "pathfinding," "BFS," "movement_cell." Build log entries use whatever the topic du jour was called.
2. **Search by file or autoload name.** If you're touching `event_scheduler.gd`, run `--search "event_scheduler"` and `--search "EventScheduler"` — both forms show up across the corpus.
3. **Run `--for-task` even when you think you know.** Token-cheap insurance against the "I would never have found that" failure.

## Bundled resources

- `scripts/build_log_index.py` — the query tool. Stdlib only. Auto-detects the log path relative to the script's install location.
- `references/entry_template.md` — canonical entry template with field-by-field guidance.
