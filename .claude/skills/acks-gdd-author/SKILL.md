---
name: acks-gdd-author
description: Draft new ACKS Arbiter Game Design Documents (GDDs) in the project's format, OR refactor existing GDDs while preserving their ACKS Constraints sections. Use this skill whenever the user asks to draft, write, sketch, outline, or revise a GDD; whenever a new system, feature, or mechanic needs documentation in generation/; whenever an existing generation/gdd-*.md needs updates, restructuring, or modernization; whenever you're about to write a section that really belongs in a GDD; or whenever the conversation has produced enough design detail that the natural next step is capturing it. Produces FULL FIRST DRAFTS (not skeletons) by default, invokes acks-raw-lookup for every ACKS rule reference, and flags architectural concerns inline. Does NOT decide whether a GDD is needed — once one is requested it produces the document. Do not draft GDDs ad-hoc; ad-hoc drafts drift from the project's format and lose value over time.
---

# ACKS Arbiter GDD Author

## Why this skill exists

The ACKS Arbiter project's design documents live in `generation/gdd-*.md` and follow a specific format: structured header, optional ACKS Constraints section, project-designed sections, citations to `rules/*.xml`. Without a forcing function, new GDDs drift from the established format — missing header fields, inconsistent citation style, conflated rule-vs-design content, no architectural context. Old GDDs that get casually updated lose the markers that distinguished RAW-derived constraints from project decisions.

This skill is the housekeeping function: keep the corpus coherent so future Claude Code build sessions and future Cowork planning sessions can find, read, and trust what's there. If the GDD format ever needs to evolve, this skill (and the bundled template) is the place that change is documented.

## When to use

Use this skill whenever Jedidiah:

- Asks for a new GDD on a system, feature, or mechanic.
- Asks to capture a conversation's design output into `generation/`.
- Asks to refactor, revise, or modernize an existing GDD.
- Asks to update an existing GDD with new status, new content, or new architectural detail.
- Asks to replace one GDD with another (the new GDD declares the `Replaces:` field).
- Asks to combine, split, or reorganize multiple GDDs.

Use it proactively when the conversation has produced 2+ paragraphs of design content that naturally belongs in a GDD — offer to draft it. Don't wait to be asked if the work is clearly heading there.

Do NOT use this skill for:

- Documentation that belongs in `docs/` (architecture briefs, system maps, coding conventions).
- Rule extracts — those go in `rules/*.xml` only when Jedidiah authors them from the books.
- Build log entries (the build log skill, when written, owns that).
- Implementation prompts for Claude Code (separate skill, `acks-build-prompt`, when written).
- GDScript or any code — that's Claude Code's job.

## Two modes

Identify which applies before doing anything else. Ask if ambiguous.

### Mode A — New GDD

The user wants a GDD that doesn't exist yet. Output is a new file at `generation/gdd-<topic>.md`.

Process:

1. **Understand scope.** If the topic is broad ("draft a GDD for combat") or could split into multiple GDDs, ask clarifying questions: which system, what's in scope, what's out of scope, what other systems does it depend on, who depends on it. Don't draft a 4-page document for what should be 3 paragraphs, and don't draft 3 paragraphs for what's actually 4 documents.

2. **Survey ACKS RAW.** For every ACKS rule the system touches, invoke `acks-raw-lookup` (see that skill's body for the procedure). Collect citations + verbatim excerpts. Don't write the body until you've done the lookups; rule-from-memory drafts are exactly the failure mode this project guards against.

3. **Survey related GDDs.** Read any existing `generation/gdd-*.md` files the new GDD will reference, depend on, overlap with, or supersede. Note overlaps and dependencies for the header and for the Architectural Concerns section.

4. **Draft the header.** Use `references/gdd_template.md` as the skeleton. Fill in every applicable field; omit fields that don't apply (e.g., `Implementing files:` is omitted for not-yet-built systems). Set `Last updated:` to today's date in YYYY-MM-DD.

5. **Draft the body.** Standard order: §1 Purpose → §2 ACKS Constraints (if applicable) → §3+ Project Decisions / Generation Pipeline / Core Pillars / etc. → final section Open Questions / Architectural Concerns. Use markdown tables for stat blocks, weighted decisions, mappings, and any structured comparison. See `references/section_patterns.md` for common patterns by GDD type.

6. **Cite every rule.** Every ACKS reference gets a `rules/foo.xml:NNN-MMM` citation with a one-line gloss of what the cited section says. The citation conventions are below; the lookup procedure is in `acks-raw-lookup`.

7. **Save to `generation/gdd-<topic>.md`.** Naming: lowercase, hyphen-separated, descriptive but concise (e.g., `gdd-trap-generation.md`, `gdd-domain-economy.md`). Confirm the filename with Jedidiah if uncertain.

### Mode B — Refactor existing GDD

The user wants an existing GDD updated, restructured, or modernized.

Process:

1. **Read the existing GDD completely.** Do NOT propose changes from the title or filename alone. Read the whole file.

2. **Identify the ACKS Constraints section.** This is the project's "sacred" section within the GDD — the part that quotes the rules. You may NOT change its content unless you're correcting a citation error, in which case run `acks-raw-lookup` to verify the correct rule and propose the fix explicitly (don't quietly rewrite a citation).

3. **Identify what's changing.** Confirm with the user: scope creep, clarification, status update, approach change, dependency change, version revision? "Update this GDD" can mean six different things.

4. **Preserve the header structure.** Bump `Status:` to reflect the change. Update `Last updated:`. Add a `Replaces:` field if you're producing a renamed file. Add or update `Implementing files:` if the build has advanced.

5. **Refactor the body.** Keep section numbering parallel to the original when possible — refactors are easier to compare when section numbers align. If the structure must change significantly, note the structural change in the new GDD's status line or header.

6. **Run `acks-raw-lookup` for any new ACKS reference** that wasn't in the original. Do NOT change existing citations unless verifying them reveals an error.

7. **Note the architectural delta** in the Open Questions or a "Migration / Refactor Notes" section. Explain what's changing and why so future readers can reconstruct the decision.

## Citation conventions

These are the conventions in active use across the existing corpus. The full `acks-raw-lookup` skill body covers the lookup process; this section is the *output style* for citations inside GDDs.

- **Inline backticks** for short references: `` `rules/foo.xml:NNN-MMM` ``
- **Markdown link form** when the reader may want to click through: `[rules/foo.xml:NNN-MMM](../rules/foo.xml)`
- **Explicit `**RAW citation:**` prefix** when the citation is the headline of a paragraph: `**RAW citation:** \`rules/foo.xml:NNN-MMM\` — initiative is 1d6 + Dex bonus, high acts first.`
- **Always include a one-line gloss.** A citation without a gloss is brittle: future readers can't tell whether you read the rule or just dropped a path.
- **Cross-GDD references** use markdown links: `[gdd-other.md](gdd-other.md)`. Use just the filename; the link is relative to `generation/`.

Do NOT cite a rule unless you verified its location via `acks-raw-lookup`. The skill exists to keep GDDs honest — uncited rule claims are the exact bleed-through pattern the project guards against.

## Architectural concerns — what to flag

When drafting (either mode), watch for and flag:

- **Overlap with an existing GDD.** If the new GDD's scope intersects another GDD's scope, name the overlap. Don't quietly assume the user wants a split or a merger — flag and let the user decide.
- **Conflict with the design brief.** `docs/acks_arbiter_design_brief_v11.md` is architectural ground truth. If the draft requires deviating from it, name the deviation. Per `CLAUDE.md`: "you may NOT restructure interfaces, rename autoloads, change data models, or modify cross-system contracts without explicit approval from Jedidiah."
- **Dependencies on systems that don't exist yet.** Note the dependency and any assumed-interface contracts. The acks-arbiter-build-plan is deprecated as a phase index, but un-built dependencies are still worth flagging.
- **Implicit ACKS Constraints not surfaced.** If the body references RAW rules without surfacing them in an ACKS Constraints section, propose moving them there.
- **Banker's rounding violations.** If the design uses rounding, confirm it's banker's rounding (round half to even). Other rounding modes are a project-wide convention violation.
- **ACKS 1e terminology drift.** Watch for the bleed-through traps from `acks-raw-lookup`'s `references/bleed_through.md` (rebuke vs turn, crusader, outlands, etc.). Don't let one slip in just because it didn't come up in a lookup.

The standard place for these is a final section titled "Open Questions" or "Architectural Concerns." Don't bury them in body prose; the user should be able to see the list at the bottom of the draft.

## Default depth

Produce a **full first draft.** Not a skeleton, not a bullet outline. A document the user could check into `generation/` as-is or edit from. Reasons:

- Iterating on a full draft is faster than iterating on a skeleton — the user can cross out what they disagree with, which is easier than expanding placeholders.
- A skeleton makes it easy to under-think hard sections (the model writes "[fill in]" and moves on). A full draft forces engagement.
- The lookups happen anyway — once you've done the research, write the prose.

When the user explicitly asks for a skeleton or outline ("just give me the sections"), produce that instead. When a section truly can't be drafted without input (the user hasn't specified key parameters and asking will be faster than guessing), surface the missing input clearly rather than fabricating.

## Bundled resources

- `references/gdd_template.md` — the standard skeleton with every field annotated. Start drafts from here.
- `references/section_patterns.md` — common section structures for the four observed GDD types (RAW-implementation, generation/procedural, architecture/umbrella, aesthetic/direction) with citations to real corpus examples.

## What this skill does NOT do

- It doesn't decide that a GDD is needed.
- It doesn't approve architectural changes.
- It doesn't write code (Claude Code's job).
- It doesn't author rule extracts (those go in `rules/*.xml` from the books, by Jedidiah).
- It doesn't produce implementation prompts for Claude Code (separate skill: `acks-build-prompt`, when written).
- It doesn't maintain the `build_log.md` (separate concern).
                                                                                                                                                                             