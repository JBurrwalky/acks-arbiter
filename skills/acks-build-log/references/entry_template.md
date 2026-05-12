# Build Log Entry Template

The canonical shape of a `build_log.md` entry, with field-by-field guidance. Match this when appending a new entry at the end of a build session.

## Template

```markdown
## Session YYYY-MM-DD — Brief Title

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

## Header

```markdown
## Session YYYY-MM-DD — Brief Title
```

- ISO date.
- Em-dash (—) separator. Hyphens also work but em-dash is the corpus convention.
- Title in title case or sentence case — match what you actually did, not just the task. A title like "Settlement market price drift implementation + Q-MERC-5 resolution" is more useful than "Settlement work."
- If the same date already has entries, that's fine — multiple sessions per day are normal in this project.

## Field-by-field guidance

### `**Task:**` — required

One or two sentences naming the goal. Past tense is fine for the entry but the task itself should describe what you set out to do, even if it shifted mid-session. If the task shifted, note that in `**Completed:**` or `**Decisions made:**` rather than mutating `**Task:**`.

**Example:** `**Task:** Implement settlement market price drift per the mercantile GDD §3.6, with monthly re-roll trigger at 10% probability.`

### `**Model used:**` — almost always required

Lists which model handled which phase. Useful for retrospection ("did Sonnet do the rules interpretation? Should have been Opus.").

**Example:** `**Model used:** Sonnet 4.6 for implementation. Opus 4.6 for RAW verification pass and final review.`

Common drift to avoid: `**Model Used:**` (cap U) is non-canonical. The script `--lint` mode flags this.

### `**Completed:**` — required

Bulleted list. Be specific: cite files, functions, signals, table names. "Built the combat resolver" is less useful than "Implemented `CombatResolver.resolve_attack()` in `engine/combat/combat_resolver.gd`; added `attack_resolved` signal; updated `combat_log.gd` to listen and render."

### `**Decisions made:**` — required when applicable

Bulleted list of architectural or design decisions with rationale. The rationale matters more than the decision itself — a future session can re-derive a decision if it knows why the prior one was made.

**Use this field, not the Task field, when you decide something mid-session.**

### `**Interfaces defined or changed:**` — required when applicable

This is the field future sessions will search most. Be explicit:

- Signal: `combat_ended(outcome: Dictionary)` where outcome has keys `result`, `rounds`, `survivors`.
- Method: `Repository.fetch_party(party_id: String) -> PartyData` — returns null if not found.
- Schema: `parties` table gains `last_settlement_id` foreign key.

Naming drift across sessions is the most expensive bug class this log prevents. Write signal names, method names, and column names verbatim so search can find them later.

### `**Database changes:**` — required when applicable

If a migration was added or a schema was changed, name the migration file. If no DB change, omit or write "None."

### `**Tests added/updated:**` — required when applicable

What's covered that wasn't. If you added regression coverage for a bug, say so explicitly so future sessions can find the regression test for that bug.

### `**Known issues:**` — sometimes present

Bugs found but not fixed, edge cases deferred, things that need review. This field surfaces in `--needs-review` queries when it contains `[NEEDS-OPUS-REVIEW]`.

### `**Next session should:**` — strongly recommended

Numbered or bulleted list. This is what the *next* session reads to know what to work on. If empty, the next session has to re-derive priorities.

Common drift to avoid: `**Next Session:**` (no "should") is non-canonical. The script `--lint` mode flags this.

## Tags inside entries

### `[NEEDS-OPUS-REVIEW]`

Use anywhere in any field when Sonnet hit something that needs deeper reasoning — complex rules interaction, architectural ambiguity, math that smells off. Future sessions surface these via `--needs-review`.

Format: `[NEEDS-OPUS-REVIEW]` or `[NEEDS-OPUS-REVIEW: brief note]`. The trailing note helps future readers decide whether the flag still applies.

### Other tags observed in the corpus

These have appeared organically; use sparingly:

- `[Q-XXX-N]` — open question tokens, mostly in settlement/economy sessions.
- `[BLOCKED-ON-X]` — implementation blocked on an external decision.

Don't invent new tag schemas without checking the existing log for collisions.

## Common drift the linter catches

The `--lint` command of the indexer script flags entries with:

- Missing required field (`**Task:**` or `**Completed:**`).
- Non-canonical field name (e.g., `**Model Used:**` vs `**Model used:**`, `**Next Session:**` vs `**Next session should:**`).

The linter is non-mutating — it only reports. If you find drift in your own current entry before appending, just fix it. If you find drift in old entries, leave them alone (append-only protocol) but adapt your search strategy: the script's field matching is already case-insensitive so old drift doesn't break queries.

## Good vs bad entries

**Good (specific, future-searchable):**

```markdown
## Session 2026-05-12 — Combat resolver: backstab handling + thief skill modifier path

**Task:** Wire backstab damage multiplier into CombatResolver, ensuring it composes correctly with the Axioms thief skill modifier.
**Model used:** Sonnet 4.6.
**Completed:**
- `CombatResolver.apply_backstab_multiplier()` added; called from `resolve_attack()` when attacker has thief class and target is unaware.
- `thief_skill_modifier()` helper extracted to `class_modifiers.gd` for reuse by Sneak/Hide.
**Interfaces defined or changed:**
- `CombatResolver.resolve_attack(attack: AttackData) -> AttackResult` — AttackResult now has `backstab_applied: bool` and `backstab_multiplier: int` fields.
**Tests added/updated:**
- `test_combat_resolver_backstab.gd` — covers unaware-target, awake-target, and concurrent-with-cleave cases.
**Next session should:**
1. Add Sneak/Hide proficiency wiring now that the helper is shared.
2. Verify backstab multiplier composes correctly with Critical Strike — RAW says they don't stack; current implementation doesn't enforce it. [NEEDS-OPUS-REVIEW: Critical Strike interaction]
```

**Bad (vague, low future value):**

```markdown
## Session 2026-05-12 — Combat work

**Task:** Combat fixes.
**Completed:** Fixed backstab.
**Next session should:** More combat work.
```

The bad entry contains nothing future-searchable. No signal names, no file paths, no rationale. If a future session breaks backstab again, this entry won't help find the prior fix.
